/*
 * System Manager Tools
 * 시스템 관리 도구 모음
 * 
 * 포괄적인 시스템 관리 기능을 제공하는 통합 도구입니다.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <time.h>
#include <dirent.h>
#include <pwd.h>
#include <grp.h>
#include <syslog.h>
#include <proc/readproc.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <json-c/json.h>
#include <yaml.h>
#include <openssl/evp.h>
#include <zlib.h>
#include <curl/curl.h>
#include <sqlite3.h>

#define SYSTEM_DB_PATH "/var/lib/system_manager/system.db"
#define CONFIG_PATH "/etc/system_manager/config.yaml"
#define LOG_PATH "/var/log/system_manager.log"
#define SOCKET_PATH "/run/system_manager.sock"
#define MAX_PROCESSES 10000
#define MAX_SERVICES 500
#define MAX_USERS 1000
#define MAX_NETWORKS 100
#define BUFFER_SIZE 8192
#define MAX_COMMANDS 1000

// 프로세스 정보 구조체
typedef struct {
    pid_t pid;
    pid_t ppid;
    uid_t uid;
    gid_t gid;
    char name[256];
    char state;
    unsigned long long utime;
    unsigned long long stime;
    unsigned long long rss;
    double cpu_percent;
    double memory_percent;
    time_t start_time;
    char cmdline[1024];
    char cwd[512];
    char exe[512];
} process_info_t;

// 서비스 정보 구조체
typedef struct {
    char name[128];
    char description[256];
    char status[32]; // running, stopped, failed, enabled, disabled
    pid_t pid;
    int auto_start;
    char exec_path[512];
    char config_file[256];
    char user[64];
    char group[64];
    time_t start_time;
    int restart_count;
    char dependencies[32][128];
    int dep_count;
} service_info_t;

// 사용자 정보 구조체
typedef struct {
    char username[64];
    char full_name[128];
    char home_dir[256];
    char shell[64];
    uid_t uid;
    gid_t gid;
    int login_count;
    time_t last_login;
    char groups[16][64];
    int group_count;
    int is_active;
    int is_locked;
} user_info_t;

// 네트워크 인터페이스 구조체
typedef struct {
    char name[32];
    char ip_address[16];
    char netmask[16];
    char gateway[16];
    char mac_address[18];
    char status[16]; // up, down
    int mtu;
    long rx_bytes;
    long tx_bytes;
    long rx_packets;
    long tx_packets;
    char ipv6_address[64];
    int is_wireless;
    char ssid[64];
    int signal_strength;
} network_interface_t;

// 시스템 리소스 구조체
typedef struct {
    unsigned long long total_memory;
    unsigned long long free_memory;
    unsigned long long used_memory;
    unsigned long long total_swap;
    unsigned long long free_swap;
    double cpu_usage;
    int cpu_cores;
    double load_average[3];
    unsigned long long uptime;
    int process_count;
    int running_processes;
    int sleeping_processes;
} system_resources_t;

// 시스템 이벤트 구조체
typedef struct {
    time_t timestamp;
    char type[64];
    char source[128];
    char message[512];
    char severity[16]; // info, warning, error, critical
    char details[1024];
} system_event_t;

// 명령어 구조체
typedef struct {
    char name[128];
    char description[256];
    char command[512];
    char args[256];
    int requires_root;
    int background;
    int timeout;
    char user[64];
    char working_dir[512];
} system_command_t;

// 시스템 관리자 구조체
typedef struct {
    sqlite3 *db;
    pthread_mutex_t db_mutex;
    pthread_mutex_t log_mutex;
    int running;
    int daemon_mode;
    int socket_fd;
    process_info_t processes[MAX_PROCESSES];
    int process_count;
    service_info_t services[MAX_SERVICES];
    int service_count;
    user_info_t users[MAX_USERS];
    int user_count;
    network_interface_t networks[MAX_NETWORKS];
    int network_count;
    system_resources_t resources;
    system_command_t commands[MAX_COMMANDS];
    int command_count;
} system_manager_t;

// 전역 변수
static system_manager_t g_sys_mgr;
static volatile sig_atomic_t g_running = 1;

// 함수 선언
int init_system_manager(int daemon_mode);
int cleanup_system_manager(void);
int load_system_config(const char *config_file);
int save_system_config(const char *config_file);
int init_database(void);
int update_process_list(void);
int update_service_list(void);
int update_user_list(void);
int update_network_info(void);
int update_system_resources(void);
int monitor_processes(void);
int monitor_services(void);
int monitor_system_resources(void);
int start_service(const char *service_name);
int stop_service(const char *service_name);
int restart_service(const char *service_name);
int enable_service(const char *service_name);
int disable_service(const char *service_name);
int kill_process(pid_t pid, int signal);
int suspend_process(pid_t pid);
int resume_process(pid_t pid);
int change_priority(pid_t pid, int priority);
int create_user(const char *username, const char *password, const char *groups);
int delete_user(const char *username);
int modify_user(const char *username, user_info_t *new_info);
int lock_user(const char *username);
int unlock_user(const char *username);
int configure_network(const char *interface, network_interface_t *config);
int restart_network(void);
int scan_network_devices(void);
int backup_system(const char *backup_path);
int restore_system(const char *backup_path);
int cleanup_system(void);
int optimize_system(void);
int check_system_health(void);
int generate_report(const char *format, const char *output_file);
void* daemon_worker(void *arg);
void* monitor_worker(void *arg);
void* socket_worker(void *arg);
int handle_command(const char *command, char *response, size_t response_size);
int log_system_event(const char *type, const char *source, const char *message, const char *severity);
int send_notification(const char *message, const char *priority);
int execute_system_command(const char *command, char *output, size_t output_size);
void signal_handler(int sig);
int init_socket_server(void);
int cleanup_socket_server(void);

// 메인 함수
int main(int argc, char *argv[]) {
    int opt;
    int daemon_mode = 0;
    char config_file[256] = CONFIG_PATH;
    
    printf("System Manager v3.0\n");
    printf("시스템 관리 도구\n\n");
    
    // 커맨드 라인 인자 파싱
    while ((opt = getopt(argc, argv, "dc:")) != -1) {
        switch (opt) {
            case 'd': // 데몬 모드
                daemon_mode = 1;
                break;
            case 'c': // 설정 파일
                strncpy(config_file, optarg, sizeof(config_file) - 1);
                break;
            default:
                printf("사용법: %s [-d] [-c config_file]\n", argv[0]);
                return 1;
        }
    }
    
    // 시그널 핸들러 설정
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, signal_handler);
    
    // 시스템 관리자 초기화
    if (init_system_manager(daemon_mode) != 0) {
        fprintf(stderr, "시스템 관리자 초기화 실패\n");
        return 1;
    }
    
    // 설정 로드
    if (load_system_config(config_file) != 0) {
        printf("설정 파일 로드 실패. 기본 설정을 사용합니다.\n");
    }
    
    if (daemon_mode) {
        // 데몬 모드 실행
        printf("시스템 관리 데몬 시작...\n");
        daemon_worker(NULL);
    } else {
        // 대화형 모드
        char input[1024];
        char response[4096];
        
        printf("시스템 관리 콘솔 (종료: exit)\n");
        
        while (g_running) {
            printf("system> ");
            fflush(stdout);
            
            if (fgets(input, sizeof(input), stdin) == NULL) {
                break;
            }
            
            // 개행 문자 제거
            input[strcspn(input, "\n")] = '\0';
            
            if (strcmp(input, "exit") == 0 || strcmp(input, "quit") == 0) {
                break;
            }
            
            if (strlen(input) > 0) {
                handle_command(input, response, sizeof(response));
                if (strlen(response) > 0) {
                    printf("%s\n", response);
                }
            }
        }
    }
    
    cleanup_system_manager();
    return 0;
}

// 시스템 관리자 초기화
int init_system_manager(int daemon_mode) {
    pthread_mutex_init(&g_sys_mgr.db_mutex, NULL);
    pthread_mutex_init(&g_sys_mgr.log_mutex, NULL);
    
    g_sys_mgr.running = 1;
    g_sys_mgr.daemon_mode = daemon_mode;
    g_sys_mgr.socket_fd = -1;
    g_sys_mgr.process_count = 0;
    g_sys_mgr.service_count = 0;
    g_sys_mgr.user_count = 0;
    g_sys_mgr.network_count = 0;
    g_sys_mgr.command_count = 0;
    
    // 데이터베이스 초기화
    if (init_database() != 0) {
        fprintf(stderr, "데이터베이스 초기화 실패\n");
        return -1;
    }
    
    // 시스템 정보 초기 로드
    update_process_list();
    update_service_list();
    update_user_list();
    update_network_info();
    update_system_resources();
    
    // 소켓 서버 초기화 (데몬 모드에서만)
    if (daemon_mode) {
        if (init_socket_server() != 0) {
            fprintf(stderr, "소켓 서버 초기화 실패\n");
            return -1;
        }
    }
    
    // syslog 연결
    openlog("system_manager", LOG_PID | LOG_CONS, LOG_DAEMON);
    
    log_system_event("INFO", "system_manager", "시스템 관리자 초기화 완료", "info");
    
    return 0;
}

// 시스템 관리자 정리
int cleanup_system_manager(void) {
    g_sys_mgr.running = 0;
    
    // 소켓 서버 정리
    if (g_sys_mgr.socket_fd >= 0) {
        cleanup_socket_server();
    }
    
    // 데이터베이스 정리
    if (g_sys_mgr.db) {
        sqlite3_close(g_sys_mgr.db);
    }
    
    // 뮤텍스 정리
    pthread_mutex_destroy(&g_sys_mgr.db_mutex);
    pthread_mutex_destroy(&g_sys_mgr.log_mutex);
    
    // syslog 정리
    closelog();
    
    printf("시스템 관리자 정리 완료\n");
    return 0;
}

// 데이터베이스 초기화
int init_database(void) {
    char *err_msg = NULL;
    int rc;
    
    rc = sqlite3_open(SYSTEM_DB_PATH, &g_sys_mgr.db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "데이터베이스 열기 실패: %s\n", sqlite3_errmsg(g_sys_mgr.db));
        return -1;
    }
    
    // 테이블 생성
    const char *sql = "CREATE TABLE IF NOT EXISTS system_events ("
                      "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                      "timestamp INTEGER,"
                      "type TEXT,"
                      "source TEXT,"
                      "message TEXT,"
                      "severity TEXT,"
                      "details TEXT"
                      ");";
    
    rc = sqlite3_exec(g_sys_mgr.db, sql, NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "테이블 생성 실패: %s\n", err_msg);
        sqlite3_free(err_msg);
        sqlite3_close(g_sys_mgr.db);
        return -1;
    }
    
    return 0;
}

// 프로세스 목록 업데이트
int update_process_list(void) {
    PROCTAB *proc = openproc(PROC_FILLMEM | PROC_FILLSTAT | PROC_FILLSTATUS | PROC_FILLARG);
    proc_t *proc_info;
    int count = 0;
    
    pthread_mutex_lock(&g_sys_mgr.db_mutex);
    
    while ((proc_info = readproc(proc, NULL)) != NULL && count < MAX_PROCESSES) {
        process_info_t *proc = &g_sys_mgr.processes[count];
        
        proc->pid = proc_info->tid;
        proc->ppid = proc_info->ppid;
        proc->uid = proc_info->ruid;
        proc->gid = proc_info->rgid;
        proc->state = proc_info->state;
        proc->utime = proc_info->utime;
        proc->stime = proc_info->stime;
        proc->rss = proc_info->rss;
        proc->start_time = proc_info->start_time;
        
        if (proc_info->cmdline) {
            char cmd[1024] = "";
            for (int i = 0; proc_info->cmdline[i] != NULL; i++) {
                if (i > 0) strcat(cmd, " ");
                strcat(cmd, proc_info->cmdline[i]);
            }
            strncpy(proc->cmdline, cmd, sizeof(proc->cmdline) - 1);
        } else {
            strncpy(proc->cmdline, proc_info->cmd, sizeof(proc->cmdline) - 1);
        }
        
        strncpy(proc->name, proc_info->cmd, sizeof(proc->name) - 1);
        
        if (proc_info->cwd) {
            strncpy(proc->cwd, proc_info->cwd, sizeof(proc->cwd) - 1);
        }
        
        if (proc_info->exe) {
            strncpy(proc->exe, proc_info->exe, sizeof(proc->exe) - 1);
        }
        
        // CPU 및 메모리 사용률 계산
        // (실제로는 시간에 따른 변화를 추적해야 함)
        proc->cpu_percent = 0.0;
        proc->memory_percent = (double)proc->rss * getpagesize() / (1024 * 1024 * 1024) * 100;
        
        count++;
        freeproc(proc_info);
    }
    
    closeproc(proc);
    g_sys_mgr.process_count = count;
    
    pthread_mutex_unlock(&g_sys_mgr.db_mutex);
    
    return 0;
}

// 서비스 목록 업데이트
int update_service_list(void) {
    FILE *fp;
    char buffer[1024];
    char *token;
    int count = 0;
    
    // systemd 서비스 목록 가져오기
    fp = popen("systemctl list-units --type=service --no-pager --no-legend", "r");
    if (!fp) {
        return -1;
    }
    
    pthread_mutex_lock(&g_sys_mgr.db_mutex);
    
    while (fgets(buffer, sizeof(buffer), fp) != NULL && count < MAX_SERVICES) {
        service_info_t *service = &g_sys_mgr.services[count];
        
        // 파싱: service.service loaded active running Description
        token = strtok(buffer, " ");
        if (!token) continue;
        
        // 서비스 이름
        strncpy(service->name, token, sizeof(service->name) - 1);
        service->name[strcspn(service->name, ".")] = '\0'; // .service 제거
        
        // 상태 정보 건너뛰기
        token = strtok(NULL, " "); // loaded
        token = strtok(NULL, " "); // active/failed
        if (token) {
            strncpy(service->status, token, sizeof(service->status) - 1);
        }
        
        token = strtok(NULL, " "); // running/dead
        if (token) {
            // 추가 상태 정보
        }
        
        // 설명
        token = strtok(NULL, "\n");
        if (token) {
            strncpy(service->description, token + 1, sizeof(service->description) - 1); // 공백 제거
        }
        
        // 기본값 설정
        service->pid = 0;
        service->auto_start = 0;
        service->start_time = 0;
        service->restart_count = 0;
        service->dep_count = 0;
        
        count++;
    }
    
    pclose(fp);
    g_sys_mgr.service_count = count;
    
    pthread_mutex_unlock(&g_sys_mgr.db_mutex);
    
    return 0;
}

// 사용자 목록 업데이트
int update_user_list(void) {
    struct passwd *pw;
    struct group *gr;
    int count = 0;
    
    pthread_mutex_lock(&g_sys_mgr.db_mutex);
    
    setpwent();
    while ((pw = getpwent()) != NULL && count < MAX_USERS) {
        user_info_t *user = &g_sys_mgr.users[count];
        
        strncpy(user->username, pw->pw_name, sizeof(user->username) - 1);
        strncpy(user->full_name, pw->pw_gecos, sizeof(user->full_name) - 1);
        strncpy(user->home_dir, pw->pw_dir, sizeof(user->home_dir) - 1);
        strncpy(user->shell, pw->pw_shell, sizeof(user->shell) - 1);
        
        user->uid = pw->pw_uid;
        user->gid = pw->pw_gid;
        user->login_count = 0;
        user->last_login = 0;
        user->group_count = 0;
        user->is_active = 1;
        user->is_locked = 0;
        
        // 사용자 그룹 정보 가져오기
        setgrent();
        while ((gr = getgrent()) != NULL && user->group_count < 16) {
            for (int i = 0; gr->gr_mem[i] != NULL; i++) {
                if (strcmp(gr->gr_mem[i], user->username) == 0) {
                    strncpy(user->groups[user->group_count], gr->gr_name, sizeof(user->groups[0]) - 1);
                    user->group_count++;
                    break;
                }
            }
        }
        endgrent();
        
        count++;
    }
    endpwent();
    
    g_sys_mgr.user_count = count;
    
    pthread_mutex_unlock(&g_sys_mgr.db_mutex);
    
    return 0;
}

// 네트워크 정보 업데이트
int update_network_info(void) {
    struct ifaddrs *ifaddrs_ptr;
    struct ifaddrs *ifa;
    int count = 0;
    
    if (getifaddrs(&ifaddrs_ptr) == -1) {
        return -1;
    }
    
    pthread_mutex_lock(&g_sys_mgr.db_mutex);
    
    for (ifa = ifaddrs_ptr; ifa != NULL && count < MAX_NETWORKS; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) {
            continue;
        }
        
        if (ifa->ifa_addr->sa_family == AF_INET) {
            network_interface_t *net = &g_sys_mgr.networks[count];
            
            strncpy(net->name, ifa->ifa_name, sizeof(net->name) - 1);
            
            // IP 주소
            struct sockaddr_in *addr_in = (struct sockaddr_in *)ifa->ifa_addr;
            inet_ntop(AF_INET, &addr_in->sin_addr, net->ip_address, sizeof(net->ip_address));
            
            // 상태
            if (ifa->ifa_flags & IFF_UP) {
                strcpy(net->status, "up");
            } else {
                strcpy(net->status, "down");
            }
            
            // MTU
            net->mtu = ifa->ifa_mtu ? ifa->ifa_mtu : 1500;
            
            // 기본값 설정
            strcpy(net->netmask, "255.255.255.0");
            strcpy(net->gateway, "0.0.0.0");
            strcpy(net->mac_address, "00:00:00:00:00:00");
            net->rx_bytes = 0;
            net->tx_bytes = 0;
            net->rx_packets = 0;
            net->tx_packets = 0;
            strcpy(net->ipv6_address, "");
            net->is_wireless = 0;
            strcpy(net->ssid, "");
            net->signal_strength = 0;
            
            count++;
        }
    }
    
    freeifaddrs(ifaddrs_ptr);
    g_sys_mgr.network_count = count;
    
    pthread_mutex_unlock(&g_sys_mgr.db_mutex);
    
    return 0;
}

// 시스템 리소스 정보 업데이트
int update_system_resources(void) {
    FILE *fp;
    char buffer[1024];
    struct sysinfo si;
    struct utsname un;
    
    pthread_mutex_lock(&g_sys_mgr.db_mutex);
    
    // 시스템 정보
    if (uname(&un) == 0) {
        // CPU 코어 수
        g_sys_mgr.resources.cpu_cores = sysconf(_SC_NPROCESSORS_ONLN);
    }
    
    // 메모리 정보
    if (sysinfo(&si) == 0) {
        g_sys_mgr.resources.total_memory = si.totalram * si.mem_unit;
        g_sys_mgr.resources.free_memory = si.freeram * si.mem_unit;
        g_sys_mgr.resources.used_memory = g_sys_mgr.resources.total_memory - g_sys_mgr.resources.free_memory;
        g_sys_mgr.resources.total_swap = si.totalswap * si.mem_unit;
        g_sys_mgr.resources.free_swap = si.freeswap * si.mem_unit;
        g_sys_mgr.resources.uptime = si.uptime;
        
        // 로드 평균
        g_sys_mgr.resources.load_average[0] = si.loads[0] / 65536.0;
        g_sys_mgr.resources.load_average[1] = si.loads[1] / 65536.0;
        g_sys_mgr.resources.load_average[2] = si.loads[2] / 65536.0;
    }
    
    // CPU 사용률 (간단한 계산)
    fp = fopen("/proc/stat", "r");
    if (fp) {
        unsigned long long user, nice, system, idle, iowait, irq, softirq;
        if (fscanf(fp, "cpu %llu %llu %llu %llu %llu %llu %llu",
                   &user, &nice, &system, &idle, &iowait, &irq, &softirq) == 7) {
            unsigned long long total = user + nice + system + idle + iowait + irq + softirq;
            unsigned long long work = user + nice + system + irq + softirq;
            
            if (total > 0) {
                g_sys_mgr.resources.cpu_usage = (double)work / total * 100.0;
            } else {
                g_sys_mgr.resources.cpu_usage = 0.0;
            }
        }
        fclose(fp);
    }
    
    // 프로세스 수
    g_sys_mgr.resources.process_count = g_sys_mgr.process_count;
    g_sys_mgr.resources.running_processes = 0;
    g_sys_mgr.resources.sleeping_processes = 0;
    
    for (int i = 0; i < g_sys_mgr.process_count; i++) {
        if (g_sys_mgr.processes[i].state == 'R') {
            g_sys_mgr.resources.running_processes++;
        } else {
            g_sys_mgr.resources.sleeping_processes++;
        }
    }
    
    pthread_mutex_unlock(&g_sys_mgr.db_mutex);
    
    return 0;
}

// 명령어 처리
int handle_command(const char *command, char *response, size_t response_size) {
    char cmd[128];
    char args[512];
    char *token;
    
    // 명령어 파싱
    strncpy(cmd, command, sizeof(cmd) - 1);
    cmd[sizeof(cmd) - 1] = '\0';
    
    token = strchr(cmd, ' ');
    if (token) {
        *token = '\0';
        strncpy(args, command + strlen(cmd) + 1, sizeof(args) - 1);
        args[sizeof(args) - 1] = '\0';
    } else {
        args[0] = '\0';
    }
    
    response[0] = '\0';
    
    // 명령어 처리
    if (strcmp(cmd, "ps") == 0 || strcmp(cmd, "processes") == 0) {
        update_process_list();
        snprintf(response, response_size, "총 %d개 프로세스:\n", g_sys_mgr.process_count);
        for (int i = 0; i < min(10, g_sys_mgr.process_count); i++) {
            process_info_t *proc = &g_sys_mgr.processes[i];
            char line[256];
            snprintf(line, sizeof(line), "  %d %s %c %.1f%% %.1f%%\n",
                    proc->pid, proc->name, proc->state, proc->cpu_percent, proc->memory_percent);
            strcat(response, line);
        }
    }
    else if (strcmp(cmd, "services") == 0) {
        update_service_list();
        snprintf(response, response_size, "총 %d개 서비스:\n", g_sys_mgr.service_count);
        for (int i = 0; i < min(10, g_sys_mgr.service_count); i++) {
            service_info_t *svc = &g_sys_mgr.services[i];
            char line[256];
            snprintf(line, sizeof(line), "  %s %s - %s\n", svc->name, svc->status, svc->description);
            strcat(response, line);
        }
    }
    else if (strcmp(cmd, "users") == 0) {
        update_user_list();
        snprintf(response, response_size, "총 %d명 사용자:\n", g_sys_mgr.user_count);
        for (int i = 0; i < min(10, g_sys_mgr.user_count); i++) {
            user_info_t *user = &g_sys_mgr.users[i];
            char line[256];
            snprintf(line, sizeof(line), "  %s (%d) - %s\n", user->username, user->uid, user->full_name);
            strcat(response, line);
        }
    }
    else if (strcmp(cmd, "network") == 0) {
        update_network_info();
        snprintf(response, response_size, "네트워크 인터페이스 (%d개):\n", g_sys_mgr.network_count);
        for (int i = 0; i < g_sys_mgr.network_count; i++) {
            network_interface_t *net = &g_sys_mgr.networks[i];
            char line[256];
            snprintf(line, sizeof(line), "  %s: %s (%s)\n", net->name, net->ip_address, net->status);
            strcat(response, line);
        }
    }
    else if (strcmp(cmd, "resources") == 0 || strcmp(cmd, "top") == 0) {
        update_system_resources();
        system_resources_t *res = &g_sys_mgr.resources;
        snprintf(response, response_size,
                "시스템 리소스:\n"
                "  CPU: %d코어, 사용률 %.1f%%\n"
                "  메모리: %llu/%llu MB (%.1f%%)\n"
                "  스왑: %llu/%llu MB\n"
                "  로드: %.2f %.2f %.2f\n"
                "  프로세스: %d (실행중: %d)\n"
                "  가동시간: %llu초\n",
                res->cpu_cores, res->cpu_usage,
                (res->total_memory - res->free_memory) / (1024*1024),
                res->total_memory / (1024*1024),
                (double)res->used_memory / res->total_memory * 100.0,
                (res->total_swap - res->free_swap) / (1024*1024),
                res->total_swap / (1024*1024),
                res->load_average[0], res->load_average[1], res->load_average[2],
                res->process_count, res->running_processes,
                res->uptime);
    }
    else if (strcmp(cmd, "help") == 0) {
        snprintf(response, response_size,
                "사용 가능한 명령어:\n"
                "  ps, processes - 프로세스 목록\n"
                "  services - 서비스 목록\n"
                "  users - 사용자 목록\n"
                "  network - 네트워크 정보\n"
                "  resources, top - 시스템 리소스\n"
                "  help - 도움말\n"
                "  exit, quit - 종료");
    }
    else {
        snprintf(response, response_size, "알 수 없는 명령어: %s (help 입력)", cmd);
    }
    
    return 0;
}

// 시스템 이벤트 로그
int log_system_event(const char *type, const char *source, const char *message, const char *severity) {
    sqlite3_stmt *stmt;
    int rc;
    time_t now = time(NULL);
    
    pthread_mutex_lock(&g_sys_mgr.db_mutex);
    
    const char *sql = "INSERT INTO system_events (timestamp, type, source, message, severity, details) "
                      "VALUES (?, ?, ?, ?, ?, ?)";
    
    rc = sqlite3_prepare_v2(g_sys_mgr.db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        pthread_mutex_unlock(&g_sys_mgr.db_mutex);
        return -1;
    }
    
    sqlite3_bind_int64(stmt, 1, now);
    sqlite3_bind_text(stmt, 2, type, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, source, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, message, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, severity, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 6, "", -1, SQLITE_STATIC);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    pthread_mutex_unlock(&g_sys_mgr.db_mutex);
    
    // syslog에도 기록
    int priority = LOG_INFO;
    if (strcmp(severity, "warning") == 0) priority = LOG_WARNING;
    else if (strcmp(severity, "error") == 0) priority = LOG_ERR;
    else if (strcmp(severity, "critical") == 0) priority = LOG_CRIT;
    
    syslog(priority, "[%s] %s: %s", type, source, message);
    
    return (rc == SQLITE_DONE) ? 0 : -1;
}

// 데몬 워커 스레드
void* daemon_worker(void *arg) {
    pthread_t monitor_thread;
    pthread_t socket_thread;
    
    // 모니터링 스레드 시작
    pthread_create(&monitor_thread, NULL, monitor_worker, NULL);
    
    // 소켓 서버 스레드 시작
    if (g_sys_mgr.socket_fd >= 0) {
        pthread_create(&socket_thread, NULL, socket_worker, NULL);
    }
    
    log_system_event("INFO", "system_manager", "데몬 시작", "info");
    
    // 메인 루프
    while (g_running) {
        sleep(1);
        
        // 주기적으로 시스템 정보 업데이트
        static int counter = 0;
        if (++counter >= 30) { // 30초마다
            update_process_list();
            update_system_resources();
            counter = 0;
        }
    }
    
    // 스레드 정리
    pthread_join(monitor_thread, NULL);
    if (g_sys_mgr.socket_fd >= 0) {
        pthread_join(socket_thread, NULL);
    }
    
    log_system_event("INFO", "system_manager", "데몬 종료", "info");
    
    return NULL;
}

// 모니터링 워커 스레드
void* monitor_worker(void *arg) {
    while (g_running) {
        // 시스템 리소스 모니터링
        update_system_resources();
        
        // 임계값 체크
        if (g_sys_mgr.resources.cpu_usage > 90.0) {
            log_system_event("WARNING", "monitor", "CPU 사용률 높음", "warning");
        }
        
        if (g_sys_mgr.resources.used_memory > g_sys_mgr.resources.total_memory * 0.9) {
            log_system_event("WARNING", "monitor", "메모리 사용률 높음", "warning");
        }
        
        if (g_sys_mgr.resources.load_average[0] > g_sys_mgr.resources.cpu_cores * 2.0) {
            log_system_event("WARNING", "monitor", "시스템 로드 높음", "warning");
        }
        
        sleep(5);
    }
    
    return NULL;
}

// 소켓 서버 초기화
int init_socket_server(void) {
    struct sockaddr_un addr;
    int fd;
    
    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd == -1) {
        perror("소켓 생성 실패");
        return -1;
    }
    
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    
    // 기존 소켓 파일 제거
    unlink(SOCKET_PATH);
    
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        perror("소켓 바인드 실패");
        close(fd);
        return -1;
    }
    
    if (listen(fd, 5) == -1) {
        perror("소켓 리슨 실패");
        close(fd);
        return -1;
    }
    
    g_sys_mgr.socket_fd = fd;
    
    return 0;
}

// 소켓 서버 정리
int cleanup_socket_server(void) {
    if (g_sys_mgr.socket_fd >= 0) {
        close(g_sys_mgr.socket_fd);
        unlink(SOCKET_PATH);
        g_sys_mgr.socket_fd = -1;
    }
    
    return 0;
}

// 소켓 워커 스레드
void* socket_worker(void *arg) {
    int client_fd;
    struct sockaddr_un client_addr;
    socklen_t client_len;
    char buffer[4096];
    char response[4096];
    
    while (g_running) {
        client_len = sizeof(client_addr);
        client_fd = accept(g_sys_mgr.socket_fd, (struct sockaddr *)&client_addr, &client_len);
        
        if (client_fd == -1) {
            if (errno == EINTR) continue;
            perror("클라이언트 accept 실패");
            continue;
        }
        
        // 클라이언트 요청 처리
        ssize_t bytes = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
        if (bytes > 0) {
            buffer[bytes] = '\0';
            
            // 명령어 처리
            handle_command(buffer, response, sizeof(response));
            
            // 응답 전송
            send(client_fd, response, strlen(response), 0);
        }
        
        close(client_fd);
    }
    
    return NULL;
}

// 시그널 핸들러
void signal_handler(int sig) {
    switch (sig) {
        case SIGTERM:
        case SIGINT:
            g_running = 0;
            break;
        case SIGHUP:
            // 설정 리로드
            break;
        default:
            break;
    }
}
