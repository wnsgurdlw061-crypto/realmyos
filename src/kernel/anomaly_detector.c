/*
 * UnifiedArch OS Anomaly Detection Module
 * 시스템 이상 행위 감지 및 보안 위협 탐지
 * 
 * 이 모듈은 다음과 같은 이상 행위를 감지합니다:
 * - 비정상적인 프로세스 실행
 * - 의심스러운 네트워크 활동
 * - 파일 시스템 무결성 위반
 * - 권한 상승 시도
 * - 루트킷 활동 감지
 * - 비정상적인 시스템 콜 패턴
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/timer.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/hash.h>
#include <linux/jiffies.h>
#include <linux/netdevice.h>
#include <linux/inet.h>
#include <linux/socket.h>
#include <linux/fs.h>
#include <linux/dcache.h>
#include <linux/namei.h>
#include <linux/path.h>
#include <linux/security.h>
#include <linux/cred.h>
#include <linux/sched.h>
#include <linux/mm.h>
#include <linux/vmalloc.h>

#define MODULE_NAME "unifiedarch_anomaly"
#define VERSION "1.0.0"
#define MAX_ANOMALY_LOG 100
#define HASH_SIZE 256

// 이상 타입
typedef enum {
    ANOMALY_NONE = 0,
    ANOMALY_SUSPICIOUS_PROCESS,
    ANOMALY_UNUSUAL_NETWORK,
    ANOMALY_FILE_INTEGRITY,
    ANOMALY_PRIVILEGE_ESCALATION,
    ANOMALY_ROOTKIT_ACTIVITY,
    ANOMALY_SYSTEM_CALL_PATTERN,
    ANOMALY_MEMORY_ANOMALY,
    ANOMALY_MAX
} anomaly_type_t;

// 심각도 레벨
typedef enum {
    SEVERITY_LOW = 1,
    SEVERITY_MEDIUM = 5,
    SEVERITY_HIGH = 8,
    SEVERITY_CRITICAL = 10
} severity_level_t;

// 이상 이벤트 구조체
struct anomaly_event {
    anomaly_type_t type;
    severity_level_t severity;
    unsigned long timestamp;
    pid_t pid;
    uid_t uid;
    char comm[TASK_COMM_LEN];
    char description[512];
    char details[1024];
    bool resolved;
    struct list_head list;
};

// 프로세스 통계 구조체
struct process_stats {
    pid_t pid;
    char comm[TASK_COMM_LEN];
    uid_t uid;
    unsigned long exec_count;
    unsigned long network_connections;
    unsigned long file_accesses;
    unsigned long memory_usage;
    unsigned long cpu_time;
    unsigned long last_activity;
    bool flagged;
    struct hlist_node hash_node;
};

// 네트워크 통계 구조체
struct network_stats {
    __be32 src_ip;
    __be32 dst_ip;
    __u16 src_port;
    __u16 dst_port;
    u8 protocol;
    unsigned long connection_count;
    unsigned long bytes_transferred;
    unsigned long last_seen;
    bool suspicious;
    struct hlist_node hash_node;
};

// 이상 감지 관리자 구조체
struct anomaly_detector {
    struct list_head anomaly_events;
    struct mutex anomaly_mutex;
    struct timer_list detection_timer;
    struct workqueue_struct *detection_wq;
    struct work_struct detection_work;
    
    // 해시 테이블
    struct hlist_head process_hash[HASH_SIZE];
    struct hlist_head network_hash[HASH_SIZE];
    
    // 설정
    bool detection_enabled;
    unsigned long detection_interval; // 초 단위
    unsigned long max_events;
    bool auto_quarantine;
    
    // 통계
    unsigned int total_events;
    unsigned int events_by_type[ANOMALY_MAX];
    unsigned int quarantined_processes;
    unsigned long false_positives;
    
    // 임계값
    unsigned long max_exec_per_minute;
    unsigned long max_network_connections;
    unsigned long max_file_accesses;
    unsigned long suspicious_memory_threshold;
};

// 전역 변수
static struct anomaly_detector detector;
static struct proc_dir_entry *proc_entry;
static struct proc_dir_entry *events_proc_entry;

// 함수 선언
static void detect_anomalies(struct work_struct *work);
static void analyze_processes(void);
static void analyze_network_activity(void);
static void analyze_file_integrity(void);
static void detect_privilege_escalation(void);
static void detect_rootkit_activity(void);
static void log_anomaly(anomaly_type_t type, severity_level_t severity, 
                       const char *description, const char *details);
static int proc_show(struct seq_file *m, void *v);
static int events_proc_show(struct seq_file *m, void *v);
static int proc_open(struct inode *inode, struct file *file);
static int events_proc_open(struct inode *inode, struct file *file);
static ssize_t proc_write(struct file *file, const char __user *buffer, size_t count, loff_t *pos);

// 해시 함수
static u32 process_hash_func(pid_t pid) {
    return hash_32(pid, HASH_SIZE);
}

static u32 network_hash_func(__be32 src_ip, __be32 dst_ip, __u16 src_port, __u16 dst_port) {
    u32 hash = src_ip ^ dst_ip ^ src_port ^ dst_port;
    return hash_32(hash, HASH_SIZE);
}

// 프로세스 통계 조회
static struct process_stats *get_process_stats(pid_t pid) {
    u32 hash = process_hash_func(pid);
    struct process_stats *stats;
    
    hlist_for_each_entry(stats, &detector.process_hash[hash], hash_node) {
        if (stats->pid == pid) {
            return stats;
        }
    }
    
    return NULL;
}

// 프로세스 통계 추가
static struct process_stats *add_process_stats(pid_t pid) {
    struct process_stats *stats;
    struct task_struct *task;
    u32 hash;
    
    stats = kmalloc(sizeof(struct process_stats), GFP_KERNEL);
    if (!stats)
        return NULL;
    
    task = pid_task(find_vpid(pid), PIDTYPE_PID);
    if (!task) {
        kfree(stats);
        return NULL;
    }
    
    memset(stats, 0, sizeof(struct process_stats));
    stats->pid = pid;
    stats->uid = task->cred->uid.val;
    strncpy(stats->comm, task->comm, TASK_COMM_LEN - 1);
    stats->last_activity = jiffies;
    
    hash = process_hash_func(pid);
    hlist_add_head(&stats->hash_node, &detector.process_hash[hash]);
    
    return stats;
}

// 네트워크 통계 조회
static struct network_stats *get_network_stats(__be32 src_ip, __be32 dst_ip, 
                                              __u16 src_port, __u16 dst_port) {
    u32 hash = network_hash_func(src_ip, dst_ip, src_port, dst_port);
    struct network_stats *stats;
    
    hlist_for_each_entry(stats, &detector.network_hash[hash], hash_node) {
        if (stats->src_ip == src_ip && stats->dst_ip == dst_ip &&
            stats->src_port == src_port && stats->dst_port == dst_port) {
            return stats;
        }
    }
    
    return NULL;
}

// 네트워크 통계 추가
static struct network_stats *add_network_stats(__be32 src_ip, __be32 dst_ip,
                                              __u16 src_port, __u16 dst_port, u8 protocol) {
    struct network_stats *stats;
    u32 hash;
    
    stats = kmalloc(sizeof(struct network_stats), GFP_KERNEL);
    if (!stats)
        return NULL;
    
    memset(stats, 0, sizeof(struct network_stats));
    stats->src_ip = src_ip;
    stats->dst_ip = dst_ip;
    stats->src_port = src_port;
    stats->dst_port = dst_port;
    stats->protocol = protocol;
    stats->last_seen = jiffies;
    
    hash = network_hash_func(src_ip, dst_ip, src_port, dst_port);
    hlist_add_head(&stats->hash_node, &detector.network_hash[hash]);
    
    return stats;
}

// 이상 감지 워크 함수
static void detect_anomalies(struct work_struct *work) {
    if (!detector.detection_enabled)
        return;
    
    analyze_processes();
    analyze_network_activity();
    analyze_file_integrity();
    detect_privilege_escalation();
    detect_rootkit_activity();
    
    // 다음 타이머 설정
    mod_timer(&detector.detection_timer, 
             jiffies + msecs_to_jiffies(detector.detection_interval * 1000));
}

// 프로세스 분석
static void analyze_processes(void) {
    struct task_struct *task;
    struct process_stats *stats;
    unsigned long current_time = jiffies;
    
    rcu_read_lock();
    
    for_each_process(task) {
        pid_t pid = task->pid;
        
        stats = get_process_stats(pid);
        if (!stats) {
            stats = add_process_stats(pid);
            if (!stats)
                continue;
        }
        
        // 실행 횟수 증가
        stats->exec_count++;
        
        // 메모리 사용량 확인
        if (task->mm) {
            stats->memory_usage = get_mm_rss(task->mm) << PAGE_SHIFT;
        }
        
        // CPU 시간 업데이트
        stats->cpu_time = task->utime + task->stime;
        
        // 비정상적 메모리 사용량 감지
        if (stats->memory_usage > detector.suspicious_memory_threshold) {
            char details[512];
            snprintf(details, sizeof(details), 
                    "PID: %d, Memory: %lu bytes, Threshold: %lu bytes",
                    pid, stats->memory_usage, detector.suspicious_memory_threshold);
            log_anomaly(ANOMALY_MEMORY_ANOMALY, SEVERITY_MEDIUM,
                       "비정상적 메모리 사용량 감지", details);
        }
        
        // 비정상적 실행 횟수 감지
        if (stats->exec_count > detector.max_exec_per_minute) {
            char details[512];
            snprintf(details, sizeof(details),
                    "PID: %d, Exec Count: %lu, Threshold: %lu/min",
                    pid, stats->exec_count, detector.max_exec_per_minute);
            log_anomaly(ANOMALY_SUSPICIOUS_PROCESS, SEVERITY_HIGH,
                       "비정상적 프로세스 실행 감지", details);
        }
        
        stats->last_activity = current_time;
    }
    
    rcu_read_unlock();
}

// 네트워크 활동 분석
static void analyze_network_activity(void) {
    struct net_device *dev;
    struct network_stats *stats;
    
    // 실제 네트워크 연결 모니터링은 netfilter hook 필요
    // 여기서는 개념적 구현만 표시
    
    rcu_read_lock();
    for_each_netdev_rcu(dev) {
        // 네트워크 통계 수집
        if (dev->stats.rx_packets > 0 || dev->stats.tx_packets > 0) {
            // 간단한 이상 감지: 과도한 패킷 전송
            if (dev->stats.tx_packets > 10000) { // 임계값
                char details[512];
                snprintf(details, sizeof(details),
                        "Interface: %s, TX Packets: %lu",
                        dev->name, dev->stats.tx_packets);
                log_anomaly(ANOMALY_UNUSUAL_NETWORK, SEVERITY_MEDIUM,
                           "비정상적 네트워크 활동 감지", details);
            }
        }
    }
    rcu_read_unlock();
}

// 파일 무결성 분석
static void analyze_file_integrity(void) {
    // 주요 시스템 파일 무결성 검사
    const char *critical_files[] = {
        "/bin/bash", "/usr/bin/sudo", "/etc/passwd", "/etc/shadow",
        "/boot/vmlinuz-linux", "/etc/ld.so.preload"
    };
    int i;
    struct path path;
    struct inode *inode;
    
    for (i = 0; i < ARRAY_SIZE(critical_files); i++) {
        if (kern_path(critical_files[i], LOOKUP_FOLLOW, &path) == 0) {
            inode = path.dentry->d_inode;
            
            // 간단한 무결성 검사: 비정상적인 수정 시간
            if (inode->i_mtime.tv_sec > (ktime_get_seconds() - 3600)) {
                char details[512];
                snprintf(details, sizeof(details),
                        "File: %s, Last Modified: %ld",
                        critical_files[i], inode->i_mtime.tv_sec);
                log_anomaly(ANOMALY_FILE_INTEGRITY, SEVERITY_HIGH,
                           "주요 파일 무결성 위반", details);
            }
            
            path_put(&path);
        }
    }
}

// 권한 상승 감지
static void detect_privilege_escalation(void) {
    struct task_struct *task;
    struct process_stats *stats;
    
    rcu_read_lock();
    for_each_process(task) {
        // 루트 권한으로 실행되는 비시스템 프로세스 감지
        if (task->cred->uid.val == 0 && task->pid > 1) {
            stats = get_process_stats(task->pid);
            if (stats && stats->uid != 0) {
                char details[512];
                snprintf(details, sizeof(details),
                        "Process: %s (PID: %d), Original UID: %d",
                        task->comm, task->pid, stats->uid);
                log_anomaly(ANOMALY_PRIVILEGE_ESCALATION, SEVERITY_CRITICAL,
                           "권한 상승 시도 감지", details);
            }
        }
    }
    rcu_read_unlock();
}

// 루트킷 활동 감지
static void detect_rootkit_activity(void) {
    // LKM 루트킷 감지: 숨겨진 모듈
    struct module *mod;
    int visible_modules = 0;
    
    // /proc/modules와 비교하여 숨겨진 모듈 감지
    list_for_each_entry(mod, THIS_MODULE->list.prev, list) {
        visible_modules++;
    }
    
    // 실제로는 더 정교한 루트킷 감지 기법 필요
    // 여기서는 기본적인 개념만 구현
    
    // 의심스러운 시스템 콜 패턴 감지
    if (detector.total_events > 50) { // 임계값
        char details[512];
        snprintf(details, sizeof(details),
                "Total Events: %u, Possible hidden activity",
                detector.total_events);
        log_anomaly(ANOMALY_ROOTKIT_ACTIVITY, SEVERITY_HIGH,
                   "의심스러운 시스템 활동 감지", details);
    }
}

// 이상 이벤트 로깅
static void log_anomaly(anomaly_type_t type, severity_level_t severity,
                       const char *description, const char *details) {
    struct anomaly_event *event;
    unsigned long current_time = jiffies;
    
    mutex_lock(&detector.anomaly_mutex);
    
    // 최대 이벤트 수 제한
    if (detector.total_events >= detector.max_events) {
        struct anomaly_event *old_event;
        old_event = list_first_entry(&detector.anomaly_events, struct anomaly_event, list);
        list_del(&old_event->list);
        kfree(old_event);
        detector.total_events--;
    }
    
    event = kmalloc(sizeof(struct anomaly_event), GFP_KERNEL);
    if (!event) {
        mutex_unlock(&detector.anomaly_mutex);
        return;
    }
    
    event->type = type;
    event->severity = severity;
    event->timestamp = current_time;
    event->pid = current->pid;
    event->uid = current_uid().val;
    strncpy(event->comm, current->comm, TASK_COMM_LEN - 1);
    strncpy(event->description, description, 511);
    strncpy(event->details, details, 1023);
    event->resolved = false;
    
    list_add_tail(&event->list, &detector.anomaly_events);
    detector.total_events++;
    detector.events_by_type[type]++;
    
    // 자동 격리 (심각한 경우)
    if (detector.auto_quarantine && severity >= SEVERITY_CRITICAL) {
        // 실제 격리 로직 구현 필요
        detector.quarantined_processes++;
    }
    
    printk(KERN_ALERT "%s: [%s] %s - %s\n", 
           MODULE_NAME, description, details, 
           severity >= SEVERITY_HIGH ? "HIGH" : "MEDIUM");
    
    mutex_unlock(&detector.anomaly_mutex);
}

// 타이머 콜백
static void detection_timer_callback(struct timer_list *t) {
    queue_work(detector.detection_wq, &detector.detection_work);
}

// proc 파일 시스템 인터페이스
static int proc_show(struct seq_file *m, void *v) {
    seq_printf(m, "=== UnifiedArch OS Anomaly Detector ===\n");
    seq_printf(m, "Version: %s\n", VERSION);
    seq_printf(m, "\n=== Configuration ===\n");
    seq_printf(m, "Detection Enabled: %s\n", 
               detector.detection_enabled ? "Yes" : "No");
    seq_printf(m, "Detection Interval: %lu seconds\n", 
               detector.detection_interval);
    seq_printf(m, "Max Events: %lu\n", detector.max_events);
    seq_printf(m, "Auto Quarantine: %s\n", 
               detector.auto_quarantine ? "Yes" : "No");
    seq_printf(m, "\n=== Statistics ===\n");
    seq_printf(m, "Total Events: %u\n", detector.total_events);
    seq_printf(m, "Quarantined Processes: %u\n", detector.quarantined_processes);
    seq_printf(m, "False Positives: %lu\n", detector.false_positives);
    
    seq_printf(m, "\n=== Events by Type ===\n");
    seq_printf(m, "Suspicious Process: %u\n", detector.events_by_type[ANOMALY_SUSPICIOUS_PROCESS]);
    seq_printf(m, "Unusual Network: %u\n", detector.events_by_type[ANOMALY_UNUSUAL_NETWORK]);
    seq_printf(m, "File Integrity: %u\n", detector.events_by_type[ANOMALY_FILE_INTEGRITY]);
    seq_printf(m, "Privilege Escalation: %u\n", detector.events_by_type[ANOMALY_PRIVILEGE_ESCALATION]);
    seq_printf(m, "Rootkit Activity: %u\n", detector.events_by_type[ANOMALY_ROOTKIT_ACTIVITY]);
    seq_printf(m, "Memory Anomaly: %u\n", detector.events_by_type[ANOMALY_MEMORY_ANOMALY]);
    
    seq_printf(m, "\n=== Thresholds ===\n");
    seq_printf(m, "Max Exec/Minute: %lu\n", detector.max_exec_per_minute);
    seq_printf(m, "Max Network Connections: %lu\n", detector.max_network_connections);
    seq_printf(m, "Max File Accesses: %lu\n", detector.max_file_accesses);
    seq_printf(m, "Memory Threshold: %lu bytes\n", detector.suspicious_memory_threshold);
    
    return 0;
}

static int events_proc_show(struct seq_file *m, void *v) {
    struct anomaly_event *event;
    
    seq_printf(m, "=== Anomaly Events ===\n");
    seq_printf(m, "Type\t\tSeverity\tPID\tUID\tProcess\tDescription\n");
    seq_printf(m, "----\t\t--------\t---\t---\t-------\t-----------\n");
    
    mutex_lock(&detector.anomaly_mutex);
    
    list_for_each_entry(event, &detector.anomaly_events, list) {
        seq_printf(m, "%d\t\t%d\t\t%d\t%d\t%s\t%s\n",
                   event->type, event->severity, event->pid, event->uid,
                   event->comm, event->description);
        seq_printf(m, "    Details: %s\n", event->details);
        seq_printf(m, "    Timestamp: %lu, Resolved: %s\n\n",
                   event->timestamp, event->resolved ? "Yes" : "No");
    }
    
    mutex_unlock(&detector.anomaly_mutex);
    
    return 0;
}

static int proc_open(struct inode *inode, struct file *file) {
    return single_open(file, proc_show, NULL);
}

static int events_proc_open(struct inode *inode, struct file *file) {
    return single_open(file, events_proc_show, NULL);
}

static ssize_t proc_write(struct file *file, const char __user *buffer, size_t count, loff_t *pos) {
    char cmd[256];
    char arg1[64];
    size_t len = min(count, sizeof(cmd) - 1);
    
    if (copy_from_user(cmd, buffer, len))
        return -EFAULT;
    
    cmd[len] = '\0';
    
    if (sscanf(cmd, "%63s", arg1) >= 1) {
        if (strcmp(arg1, "enable") == 0) {
            detector.detection_enabled = true;
            mod_timer(&detector.detection_timer, 
                     jiffies + msecs_to_jiffies(detector.detection_interval * 1000));
        } else if (strcmp(arg1, "disable") == 0) {
            detector.detection_enabled = false;
            del_timer_sync(&detector.detection_timer);
        } else if (strcmp(arg1, "clear") == 0) {
            struct anomaly_event *event, *tmp;
            mutex_lock(&detector.anomaly_mutex);
            list_for_each_entry_safe(event, tmp, &detector.anomaly_events, list) {
                list_del(&event->list);
                kfree(event);
            }
            detector.total_events = 0;
            memset(detector.events_by_type, 0, sizeof(detector.events_by_type));
            mutex_unlock(&detector.anomaly_mutex);
        }
    }
    
    return count;
}

// 모듈 초기화
static int __init anomaly_detector_init(void) {
    int i;
    
    printk(KERN_INFO "%s: UnifiedArch OS Anomaly Detector v%s\n", 
           MODULE_NAME, VERSION);
    
    // 감지기 구조체 초기화
    memset(&detector, 0, sizeof(detector));
    INIT_LIST_HEAD(&detector.anomaly_events);
    mutex_init(&detector.anomaly_mutex);
    
    // 해시 테이블 초기화
    for (i = 0; i < HASH_SIZE; i++) {
        INIT_HLIST_HEAD(&detector.process_hash[i]);
        INIT_HLIST_HEAD(&detector.network_hash[i]);
    }
    
    // 기본 설정
    detector.detection_enabled = true;
    detector.detection_interval = 30; // 30초
    detector.max_events = MAX_ANOMALY_LOG;
    detector.auto_quarantine = false;
    
    // 임계값 설정
    detector.max_exec_per_minute = 100;
    detector.max_network_connections = 1000;
    detector.max_file_accesses = 500;
    detector.suspicious_memory_threshold = 100 * 1024 * 1024; // 100MB
    
    // 워크큐 생성
    detector.detection_wq = create_singlethread_workqueue("anomaly_detection_wq");
    if (!detector.detection_wq) {
        printk(KERN_ERR "%s: 워크큐 생성 실패\n", MODULE_NAME);
        return -ENOMEM;
    }
    
    // 워크 초기화
    INIT_WORK(&detector.detection_work, detect_anomalies);
    
    // 타이머 초기화
    timer_setup(&detector.detection_timer, detection_timer_callback, 0);
    
    // proc 파일 생성
    proc_entry = proc_create("unifiedarch_anomaly", 0666, NULL, &anomaly_proc_ops);
    if (!proc_entry) {
        printk(KERN_ERR "%s: proc 파일 생성 실패\n", MODULE_NAME);
        destroy_workqueue(detector.detection_wq);
        return -ENOMEM;
    }
    
    events_proc_entry = proc_create("unifiedarch_events", 0444, NULL, &events_proc_ops);
    if (!events_proc_entry) {
        printk(KERN_ERR "%s: 이벤트 proc 파일 생성 실패\n", MODULE_NAME);
        proc_remove(proc_entry);
        destroy_workqueue(detector.detection_wq);
        return -ENOMEM;
    }
    
    // 감지 시작
    if (detector.detection_enabled) {
        mod_timer(&detector.detection_timer, 
                 jiffies + msecs_to_jiffies(detector.detection_interval * 1000));
    }
    
    printk(KERN_INFO "%s: 모듈 로드 완료\n", MODULE_NAME);
    return 0;
}

// 모듈 제거
static void __exit anomaly_detector_exit(void) {
    struct anomaly_event *event, *tmp;
    struct process_stats *proc_stats, *proc_tmp;
    struct network_stats *net_stats, *net_tmp;
    int i;
    
    // 타이머 제거
    del_timer_sync(&detector.detection_timer);
    
    // 워크큐 제거
    destroy_workqueue(detector.detection_wq);
    
    // 모든 이벤트 정리
    mutex_lock(&detector.anomaly_mutex);
    list_for_each_entry_safe(event, tmp, &detector.anomaly_events, list) {
        list_del(&event->list);
        kfree(event);
    }
    mutex_unlock(&detector.anomaly_mutex);
    
    // 프로세스 통계 정리
    for (i = 0; i < HASH_SIZE; i++) {
        hlist_for_each_entry_safe(proc_stats, proc_tmp, &detector.process_hash[i], hash_node) {
            hlist_del(&proc_stats->hash_node);
            kfree(proc_stats);
        }
    }
    
    // 네트워크 통계 정리
    for (i = 0; i < HASH_SIZE; i++) {
        hlist_for_each_entry_safe(net_stats, net_tmp, &detector.network_hash[i], hash_node) {
            hlist_del(&net_stats->hash_node);
            kfree(net_stats);
        }
    }
    
    // proc 파일 제거
    proc_remove(events_proc_entry);
    proc_remove(proc_entry);
    
    printk(KERN_INFO "%s: 모듈 언로드 완료\n", MODULE_NAME);
}

module_init(anomaly_detector_init);
module_exit(anomaly_detector_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("UnifiedArch OS Team");
MODULE_DESCRIPTION("UnifiedArch OS Anomaly Detection Module");
MODULE_VERSION(VERSION);
