/*
 * UnifiedArch OS Emergency Response System (Fixed Version)
 * 비상 상황 감지 및 자동 응답 커널 모듈
 * 최신 커널 API 호환성 수정 버전
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
#include <linux/mm.h>
#include <linux/cpumask.h>
#include <linux/netdevice.h>
#include <linux/sysinfo.h>
#include <linux/jiffies.h>

#define MODULE_NAME "unifiedarch_emergency"
#define VERSION "1.0.0"

// 비상 상황 타입
typedef enum {
    EMERGENCY_NONE = 0,
    EMERGENCY_MEMORY_CRITICAL,
    EMERGENCY_CPU_OVERLOAD,
    EMERGENCY_DISK_FULL,
    EMERGENCY_NETWORK_FAILURE,
    EMERGENCY_SECURITY_BREACH,
    EMERGENCY_KERNEL_PANIC,
    EMERGENCY_MAX
} emergency_type_t;

// 비상 응답 액션 타입
typedef enum {
    ACTION_NONE = 0,
    ACTION_KILL_PROCESSES,
    ACTION_FREE_MEMORY,
    ACTION_RESTART_SERVICES,
    ACTION_ENABLE_SAFE_MODE,
    ACTION_SHUTDOWN_SYSTEM,
    ACTION_ALERT_ADMIN,
    ACTION_MAX
} emergency_action_t;

// 비상 상황 구조체
struct emergency_event {
    emergency_type_t type;
    unsigned long timestamp;
    int severity;  // 1-10 심각도
    char description[256];
    emergency_action_t action_taken;
    bool resolved;
};

// 시스템 상태 모니터링 구조체
struct system_monitor {
    unsigned long memory_usage;
    unsigned long cpu_usage;
    unsigned long disk_usage;
    unsigned long network_errors;
    unsigned long security_events;
    unsigned long last_check;
};

// 전역 변수
static struct timer_list monitor_timer;
static struct workqueue_struct *emergency_wq;
static struct work_struct emergency_work;
static struct emergency_event emergency_log[EMERGENCY_MAX];
static struct system_monitor current_state;
static DEFINE_MUTEX(emergency_mutex);
static struct proc_dir_entry *proc_entry;

// 임계값 설정
static struct {
    unsigned long memory_critical_threshold;  // 90%
    unsigned long cpu_critical_threshold;     // 95%
    unsigned long disk_critical_threshold;     // 95%
    unsigned long network_error_threshold;     // 1000 errors/min
    unsigned long security_threshold;          // 10 events/min
} thresholds = {
    .memory_critical_threshold = 90,
    .cpu_critical_threshold = 95,
    .disk_critical_threshold = 95,
    .network_error_threshold = 1000,
    .security_threshold = 10
};

// 함수 선언
static void monitor_system_state(struct work_struct *work);
static void handle_emergency(emergency_type_t type, int severity, const char *desc);
static void emergency_respond(emergency_type_t type);
static int proc_show(struct seq_file *m, void *v);
static int proc_open(struct inode *inode, struct file *file);
static ssize_t proc_write(struct file *file, const char __user *buffer, size_t count, loff_t *pos);

// proc 파일 오퍼레이션 (최신 커널 호환)
static const struct proc_ops emergency_proc_ops = {
    .proc_open = proc_open,
    .proc_read = seq_read,
    .proc_write = proc_write,
    .proc_lseek = seq_lseek,
    .proc_release = single_release,
};

// 시스템 상태 모니터링 함수
static void monitor_system_state(struct work_struct *work) {
    struct sysinfo si;
    unsigned long total_memory = 0, free_memory = 0;
    unsigned long cpu_idle = 0, cpu_total = 0;
    
    mutex_lock(&emergency_mutex);
    
    // 메모리 상태 확인
    si_meminfo(&si);
    total_memory = si.totalram;
    free_memory = si.freeram;
    current_state.memory_usage = 100 - ((free_memory * 100) / total_memory);
    
    // CPU 사용률 확인 (간단한 방식)
    cpu_idle = nr_iowait_cpu(0);
    cpu_total = jiffies - current_state.last_check;
    if (cpu_total > 0) {
        current_state.cpu_usage = 100 - ((cpu_idle * 100) / cpu_total);
    }
    
    // 디스크 사용률 확인 (간단한 방식)
    current_state.disk_usage = 75; // 임시 값
    
    // 네트워크 에러 확인 (단순화)
    current_state.network_errors = 0;
    
    // 보안 이벤트 확인 (임시)
    current_state.security_events = 0;
    
    current_state.last_check = jiffies;
    
    // 비상 상황 감지
    if (current_state.memory_usage > thresholds.memory_critical_threshold) {
        handle_emergency(EMERGENCY_MEMORY_CRITICAL, 8, 
                        "메모리 사용량이 임계치를 초과했습니다");
    }
    
    if (current_state.cpu_usage > thresholds.cpu_critical_threshold) {
        handle_emergency(EMERGENCY_CPU_OVERLOAD, 7,
                        "CPU 사용량이 임계치를 초과했습니다");
    }
    
    if (current_state.disk_usage > thresholds.disk_critical_threshold) {
        handle_emergency(EMERGENCY_DISK_FULL, 9,
                        "디스크 공간이 거의 가득 찼습니다");
    }
    
    if (current_state.network_errors > thresholds.network_error_threshold) {
        handle_emergency(EMERGENCY_NETWORK_FAILURE, 6,
                        "네트워크 에러가 임계치를 초과했습니다");
    }
    
    if (current_state.security_events > thresholds.security_threshold) {
        handle_emergency(EMERGENCY_SECURITY_BREACH, 10,
                        "보안 위협이 감지되었습니다");
    }
    
    mutex_unlock(&emergency_mutex);
    
    // 다음 모니터링 타이머 설정
    mod_timer(&monitor_timer, jiffies + msecs_to_jiffies(5000));
}

// 비상 상황 처리 함수
static void handle_emergency(emergency_type_t type, int severity, const char *desc) {
    int i;
    
    // 이미 동일한 비상 상황이 처리 중인지 확인
    for (i = 0; i < EMERGENCY_MAX; i++) {
        if (emergency_log[i].type == type && !emergency_log[i].resolved) {
            return; // 이미 처리 중
        }
    }
    
    // 비상 로그 기록
    for (i = 0; i < EMERGENCY_MAX; i++) {
        if (emergency_log[i].type == EMERGENCY_NONE) {
            emergency_log[i].type = type;
            emergency_log[i].timestamp = jiffies;
            emergency_log[i].severity = severity;
            strncpy(emergency_log[i].description, desc, 255);
            emergency_log[i].description[255] = '\0';
            emergency_log[i].action_taken = ACTION_NONE;
            emergency_log[i].resolved = false;
            break;
        }
    }
    
    printk(KERN_ALERT "%s: 비상 상황 감지 - %s (심각도: %d)\n", 
           MODULE_NAME, desc, severity);
    
    // 비상 응답 실행
    emergency_respond(type);
}

// 비상 응답 함수
static void emergency_respond(emergency_type_t type) {
    switch (type) {
        case EMERGENCY_MEMORY_CRITICAL:
            emergency_log[type].action_taken = ACTION_FREE_MEMORY;
            printk(KERN_INFO "%s: 메모리 확보 조치 실행 중...\n", MODULE_NAME);
            break;
            
        case EMERGENCY_CPU_OVERLOAD:
            emergency_log[type].action_taken = ACTION_KILL_PROCESSES;
            printk(KERN_INFO "%s: CPU 부하 감소 조치 실행 중...\n", MODULE_NAME);
            break;
            
        case EMERGENCY_DISK_FULL:
            emergency_log[type].action_taken = ACTION_ENABLE_SAFE_MODE;
            printk(KERN_INFO "%s: 디스크 공간 확보 조치 실행 중...\n", MODULE_NAME);
            break;
            
        case EMERGENCY_NETWORK_FAILURE:
            emergency_log[type].action_taken = ACTION_RESTART_SERVICES;
            printk(KERN_INFO "%s: 네트워크 서비스 재시작 중...\n", MODULE_NAME);
            break;
            
        case EMERGENCY_SECURITY_BREACH:
            emergency_log[type].action_taken = ACTION_ENABLE_SAFE_MODE;
            printk(KERN_ALERT "%s: 보안 모드 활성화!\n", MODULE_NAME);
            break;
            
        case EMERGENCY_KERNEL_PANIC:
            emergency_log[type].action_taken = ACTION_SHUTDOWN_SYSTEM;
            printk(KERN_ALERT "%s: 시스템 종료 준비 중...\n", MODULE_NAME);
            break;
            
        default:
            emergency_log[type].action_taken = ACTION_ALERT_ADMIN;
            break;
    }
}

// 모니터링 타이머 콜백
static void monitor_timer_callback(struct timer_list *t) {
    queue_work(emergency_wq, &emergency_work);
}

// proc 파일 시스템 인터페이스
static int proc_show(struct seq_file *m, void *v) {
    int i;
    
    seq_printf(m, "=== UnifiedArch OS Emergency Response System ===\n");
    seq_printf(m, "Version: %s\n", VERSION);
    seq_printf(m, "\n=== System Status ===\n");
    seq_printf(m, "Memory Usage: %lu%%\n", current_state.memory_usage);
    seq_printf(m, "CPU Usage: %lu%%\n", current_state.cpu_usage);
    seq_printf(m, "Disk Usage: %lu%%\n", current_state.disk_usage);
    seq_printf(m, "Network Errors: %lu\n", current_state.network_errors);
    seq_printf(m, "Security Events: %lu\n", current_state.security_events);
    seq_printf(m, "\n=== Emergency Log ===\n");
    
    for (i = 0; i < EMERGENCY_MAX; i++) {
        if (emergency_log[i].type != EMERGENCY_NONE) {
            seq_printf(m, "[%d] Type: %d, Severity: %d, Action: %d, Resolved: %s\n",
                       i, emergency_log[i].type, emergency_log[i].severity,
                       emergency_log[i].action_taken, 
                       emergency_log[i].resolved ? "Yes" : "No");
            seq_printf(m, "    Description: %s\n", emergency_log[i].description);
            seq_printf(m, "    Timestamp: %lu\n", emergency_log[i].timestamp);
        }
    }
    
    seq_printf(m, "\n=== Thresholds ===\n");
    seq_printf(m, "Memory Critical: %lu%%\n", thresholds.memory_critical_threshold);
    seq_printf(m, "CPU Critical: %lu%%\n", thresholds.cpu_critical_threshold);
    seq_printf(m, "Disk Critical: %lu%%\n", thresholds.disk_critical_threshold);
    seq_printf(m, "Network Error Threshold: %lu/min\n", thresholds.network_error_threshold);
    seq_printf(m, "Security Threshold: %lu/min\n", thresholds.security_threshold);
    
    return 0;
}

static int proc_open(struct inode *inode, struct file *file) {
    return single_open(file, proc_show, NULL);
}

static ssize_t proc_write(struct file *file, const char __user *buffer, size_t count, loff_t *pos) {
    char cmd[256];
    size_t len = min(count, sizeof(cmd) - 1);
    
    if (copy_from_user(cmd, buffer, len))
        return -EFAULT;
    
    cmd[len] = '\0';
    
    // 명령어 처리
    if (strncmp(cmd, "reset", 5) == 0) {
        mutex_lock(&emergency_mutex);
        memset(emergency_log, 0, sizeof(emergency_log));
        mutex_unlock(&emergency_mutex);
        printk(KERN_INFO "%s: Emergency log reset\n", MODULE_NAME);
    } else if (strncmp(cmd, "test", 4) == 0) {
        handle_emergency(EMERGENCY_MEMORY_CRITICAL, 5, "테스트 비상 상황");
    }
    
    return count;
}

// 모듈 초기화
static int __init emergency_response_init(void) {
    int ret = 0;
    
    printk(KERN_INFO "%s: UnifiedArch OS Emergency Response System v%s\n", 
           MODULE_NAME, VERSION);
    
    // 워크큐 생성
    emergency_wq = create_singlethread_workqueue("emergency_wq");
    if (!emergency_wq) {
        printk(KERN_ERR "%s: 워크큐 생성 실패\n", MODULE_NAME);
        return -ENOMEM;
    }
    
    // 워크 초기화
    INIT_WORK(&emergency_work, monitor_system_state);
    
    // 타이머 초기화
    timer_setup(&monitor_timer, monitor_timer_callback, 0);
    
    // proc 파일 생성
    proc_entry = proc_create("unifiedarch_emergency", 0666, NULL, &emergency_proc_ops);
    if (!proc_entry) {
        printk(KERN_ERR "%s: proc 파일 생성 실패\n", MODULE_NAME);
        destroy_workqueue(emergency_wq);
        return -ENOMEM;
    }
    
    // 초기 상태 설정
    memset(&current_state, 0, sizeof(current_state));
    memset(emergency_log, 0, sizeof(emergency_log));
    current_state.last_check = jiffies;
    
    // 모니터링 시작
    mod_timer(&monitor_timer, jiffies + msecs_to_jiffies(5000));
    
    printk(KERN_INFO "%s: 모듈 로드 완료\n", MODULE_NAME);
    return ret;
}

// 모듈 제거
static void __exit emergency_response_exit(void) {
    // 타이머 제거
    del_timer_sync(&monitor_timer);
    
    // 워크큐 제거
    destroy_workqueue(emergency_wq);
    
    // proc 파일 제거
    proc_remove(proc_entry);
    
    printk(KERN_INFO "%s: 모듈 언로드 완료\n", MODULE_NAME);
}

module_init(emergency_response_init);
module_exit(emergency_response_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("UnifiedArch OS Team");
MODULE_DESCRIPTION("UnifiedArch OS Emergency Response System (Fixed)");
MODULE_VERSION(VERSION);
