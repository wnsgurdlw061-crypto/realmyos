/*
 * Advanced Installer Framework
 * 고급 설치 프레임워크
 * 
 * 이 설치 프레임워크는 복잡한 시스템 설치를 자동화하고
 * 다양한 설치 시나리오를 지원합니다.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <blkid/blkid.h>
#include <parted/parted.h>
#include <libmount/libmount.h>
#include <ncurses.h>
#include <menu.h>
#include <form.h>
#include <panel.h>
#include <libconfig.h>
#include <json-c/json.h>
#include <yaml.h>
#include <openssl/evp.h>
#include <zlib.h>

#define INSTALL_CONFIG_PATH "/etc/installer/config.yaml"
#define INSTALL_LOG_PATH "/var/log/installer.log"
#define TEMP_MOUNT_PATH "/tmp/installer"
#define MAX_PARTITIONS 32
#define MAX_USERS 100
#define BUFFER_SIZE 4096
#define MAX_INSTALL_STEPS 50

// 설치 단계 구조체
typedef struct {
    int step_id;
    char name[128];
    char description[256];
    int (*execute)(void *data);
    void *data;
    int status; // 0: pending, 1: running, 2: completed, -1: failed
    int required;
    int estimated_time; // 초 단위
} install_step_t;

// 파티션 구조체
typedef struct {
    char device[64];
    char mount_point[256];
    char filesystem[32];
    char label[64];
    unsigned long long size;
    int boot_flag;
    int encrypted;
    char encryption_key[256];
} partition_t;

// 사용자 구조체
typedef struct {
    char username[64];
    char password[256];
    char full_name[128];
    char home_dir[256];
    char shell[64];
    int uid;
    int gid;
    int sudo_access;
    int admin;
} user_t;

// 네트워크 구조체
typedef struct {
    char interface[32];
    char method[16]; // dhcp, static
    char ip_address[16];
    char netmask[16];
    char gateway[16];
    char dns[16];
    char hostname[64];
    char domain[64];
} network_config_t;

// 설치 구성 구조체
typedef struct {
    char target_device[64];
    char hostname[64];
    char locale[32];
    char timezone[64];
    char keyboard[32];
    partition_t partitions[MAX_PARTITIONS];
    int partition_count;
    user_t users[MAX_USERS];
    int user_count;
    network_config_t network;
    char bootloader[32];
    char desktop_environment[64];
    char packages[1024];
    int auto_partition;
    int encrypt_system;
    char encryption_password[256];
    int enable_ssh;
    int enable_firewall;
} install_config_t;

// 설치 상태 구조체
typedef struct {
    int current_step;
    int total_steps;
    int progress_percent;
    char status_message[256];
    time_t start_time;
    time_t estimated_completion;
    int install_complete;
    pthread_mutex_t mutex;
} install_status_t;

// 전역 변수
static install_config_t g_config;
static install_status_t g_status;
static install_step_t g_steps[MAX_INSTALL_STEPS];
static int g_step_count = 0;
static WINDOW *g_main_win = NULL;
static MENU *g_menu = NULL;
static PANEL *g_panel = NULL;

// 함수 선언
int init_installer_framework(void);
int cleanup_installer_framework(void);
int load_install_config(const char *config_file);
int save_install_config(const char *config_file);
int detect_hardware(void);
int partition_disk(void);
int format_partitions(void);
int mount_filesystems(void);
int install_base_system(void);
int configure_bootloader(void);
int create_users(void);
int configure_network(void);
int install_packages(void);
int configure_services(void);
int finalize_installation(void);
int verify_installation(void);
void* install_worker(void *arg);
void update_progress(int step, int percent, const char *message);
int show_install_menu(void);
int show_partition_editor(void);
int show_user_manager(void);
int show_network_config(void);
int log_install_message(const char *level, const char *message);
int backup_config(void);
int restore_config(const char *backup_file);
int create_recovery_partition(void);
int setup_encryption(const char *device, const char *password);
int verify_system_requirements(void);

// 메인 함수
int main(int argc, char *argv[]) {
    int opt;
    int auto_mode = 0;
    char config_file[256] = INSTALL_CONFIG_PATH;
    
    printf("Advanced Installer Framework v2.0\n");
    printf("고급 설치 프레임워크\n\n");
    
    // 커맨드 라인 인자 파싱
    while ((opt = getopt(argc, argv, "ac:")) != -1) {
        switch (opt) {
            case 'a': // 자동 모드
                auto_mode = 1;
                break;
            case 'c': // 설정 파일
                strncpy(config_file, optarg, sizeof(config_file) - 1);
                break;
            default:
                printf("사용법: %s [-a] [-c config_file]\n", argv[0]);
                return 1;
        }
    }
    
    // 설치 프레임워크 초기화
    if (init_installer_framework() != 0) {
        fprintf(stderr, "설치 프레임워크 초기화 실패\n");
        return 1;
    }
    
    // 설정 로드
    if (load_install_config(config_file) != 0) {
        printf("설정 파일 로드 실패. 기본 설정을 사용합니다.\n");
    }
    
    // 시스템 요구사항 검증
    if (verify_system_requirements() != 0) {
        fprintf(stderr, "시스템 요구사항을 충족하지 않습니다.\n");
        cleanup_installer_framework();
        return 1;
    }
    
    // 하드웨어 감지
    printf("하드웨어 감지 중...\n");
    if (detect_hardware() != 0) {
        fprintf(stderr, "하드웨어 감지 실패\n");
        cleanup_installer_framework();
        return 1;
    }
    
    if (auto_mode) {
        // 자동 설치 모드
        printf("자동 설치 시작...\n");
        install_worker(NULL);
    } else {
        // 대화형 설치 모드
        if (show_install_menu() != 0) {
            fprintf(stderr, "설치 메뉴 표시 실패\n");
            cleanup_installer_framework();
            return 1;
        }
    }
    
    cleanup_installer_framework();
    return 0;
}

// 설치 프레임워크 초기화
int init_installer_framework(void) {
    // 임시 마운트 디렉토리 생성
    if (mkdir(TEMP_MOUNT_PATH, 0755) != 0 && errno != EEXIST) {
        perror("임시 디렉토리 생성 실패");
        return -1;
    }
    
    // 상태 구조체 초기화
    pthread_mutex_init(&g_status.mutex, NULL);
    g_status.current_step = 0;
    g_status.total_steps = 0;
    g_status.progress_percent = 0;
    g_status.install_complete = 0;
    g_status.start_time = time(NULL);
    
    // 설치 단계 초기화
    memset(g_steps, 0, sizeof(g_steps));
    
    // 기본 설정 초기화
    memset(&g_config, 0, sizeof(g_config));
    strncpy(g_config.hostname, "localhost", sizeof(g_config.hostname) - 1);
    strncpy(g_config.locale, "ko_KR.UTF-8", sizeof(g_config.locale) - 1);
    strncpy(g_config.timezone, "Asia/Seoul", sizeof(g_config.timezone) - 1);
    strncpy(g_config.keyboard, "kr", sizeof(g_config.keyboard) - 1);
    strncpy(g_config.bootloader, "grub", sizeof(g_config.bootloader) - 1);
    
    log_install_message("INFO", "설치 프레임워크 초기화 완료");
    return 0;
}

// 설치 프레임워크 정리
int cleanup_installer_framework(void) {
    pthread_mutex_destroy(&g_status.mutex);
    
    // ncurses 정리
    if (g_main_win) {
        delwin(g_main_win);
        endwin();
    }
    
    // 임시 마운트 해제
    system("umount " TEMP_MOUNT_PATH " 2>/dev/null");
    
    log_install_message("INFO", "설치 프레임워크 정리 완료");
    return 0;
}

// 설치 설정 로드
int load_install_config(const char *config_file) {
    config_t cfg;
    config_setting_t *setting;
    const char *str;
    int value;
    
    config_init(&cfg);
    
    if (!config_read_file(&cfg, config_file)) {
        config_destroy(&cfg);
        return -1;
    }
    
    // 기본 설정 로드
    if (config_lookup_string(&cfg, "hostname", &str)) {
        strncpy(g_config.hostname, str, sizeof(g_config.hostname) - 1);
    }
    
    if (config_lookup_string(&cfg, "locale", &str)) {
        strncpy(g_config.locale, str, sizeof(g_config.locale) - 1);
    }
    
    if (config_lookup_string(&cfg, "timezone", &str)) {
        strncpy(g_config.timezone, str, sizeof(g_config.timezone) - 1);
    }
    
    if (config_lookup_string(&cfg, "target_device", &str)) {
        strncpy(g_config.target_device, str, sizeof(g_config.target_device) - 1);
    }
    
    if (config_lookup_int(&cfg, "auto_partition", &value)) {
        g_config.auto_partition = value;
    }
    
    if (config_lookup_int(&cfg, "encrypt_system", &value)) {
        g_config.encrypt_system = value;
    }
    
    // 파티션 설정 로드
    setting = config_lookup(&cfg, "partitions");
    if (setting) {
        int count = config_setting_length(setting);
        for (int i = 0; i < count && i < MAX_PARTITIONS; i++) {
            config_setting_t *part = config_setting_get_elem(setting, i);
            partition_t *p = &g_config.partitions[i];
            
            if (config_setting_lookup_string(part, "device", &str)) {
                strncpy(p->device, str, sizeof(p->device) - 1);
            }
            
            if (config_setting_lookup_string(part, "mount_point", &str)) {
                strncpy(p->mount_point, str, sizeof(p->mount_point) - 1);
            }
            
            if (config_setting_lookup_string(part, "filesystem", &str)) {
                strncpy(p->filesystem, str, sizeof(p->filesystem) - 1);
            }
            
            if (config_setting_lookup_int64(part, "size", (long long*)&p->size)) {
                // 크기 설정
            }
        }
        g_config.partition_count = count;
    }
    
    config_destroy(&cfg);
    log_install_message("INFO", "설치 설정 로드 완료");
    return 0;
}

// 하드웨어 감지
int detect_hardware(void) {
    FILE *fp;
    char buffer[1024];
    char device[64];
    
    // 디스크 감지
    fp = popen("lsblk -d -n -o NAME,SIZE,MODEL", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            printf("감지된 디스크: %s", buffer);
        }
        pclose(fp);
    }
    
    // 메모리 감지
    fp = fopen("/proc/meminfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "MemTotal:", 9) == 0) {
                printf("시스템 메모리: %s", buffer + 9);
                break;
            }
        }
        fclose(fp);
    }
    
    // CPU 감지
    fp = fopen("/proc/cpuinfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "model name", 10) == 0) {
                printf("CPU: %s", buffer + 13);
                break;
            }
        }
        fclose(fp);
    }
    
    log_install_message("INFO", "하드웨어 감지 완료");
    return 0;
}

// 디스크 파티셔닝
int partition_disk(void) {
    PedDevice *device;
    PedDisk *disk;
    PedPartition *part;
    PedConstraint *constraint;
    
    update_progress(1, 10, "디스크 파티셔닝 중...");
    
    if (g_config.auto_partition) {
        // 자동 파티셔닝
        printf("자동 파티셔닝 실행...\n");
        
        device = ped_device_get(g_config.target_device);
        if (!device) {
            log_install_message("ERROR", "디바이스를 찾을 수 없습니다");
            return -1;
        }
        
        disk = ped_disk_new_fresh(device, ped_disk_type_get("gpt"));
        if (!disk) {
            ped_device_destroy(device);
            log_install_message("ERROR", "디스크 생성 실패");
            return -1;
        }
        
        // EFI 파티션 (512MB)
        constraint = ped_constraint_any(device);
        part = ped_partition_new(disk, PED_PARTITION_NORMAL, NULL, 2048, 2048 + 1024*1024 - 1);
        if (part) {
            ped_partition_set_name(part, "EFI System Partition");
            ped_partition_set_flag(part, PED_PARTITION_BOOT, 1);
            ped_disk_add_partition(disk, part, constraint);
        }
        
        // 루트 파티션 (나머지 공간)
        part = ped_partition_new(disk, PED_PARTITION_NORMAL, NULL, 2048 + 1024*1024, device->length - 1);
        if (part) {
            ped_partition_set_name(part, "Root");
            ped_disk_add_partition(disk, part, constraint);
        }
        
        ped_constraint_destroy(constraint);
        ped_disk_commit_to_dev(disk);
        ped_disk_destroy(disk);
        ped_device_destroy(device);
        
        printf("자동 파티셔닝 완료\n");
    } else {
        // 수동 파티셔닝
        if (show_partition_editor() != 0) {
            log_install_message("ERROR", "파티션 편집기 실패");
            return -1;
        }
    }
    
    update_progress(1, 20, "디스크 파티셔닝 완료");
    log_install_message("INFO", "디스크 파티셔닝 완료");
    return 0;
}

// 파티션 포맷
int format_partitions(void) {
    char command[512];
    
    update_progress(2, 30, "파티션 포맷 중...");
    
    for (int i = 0; i < g_config.partition_count; i++) {
        partition_t *part = &g_config.partitions[i];
        
        if (strcmp(part->filesystem, "ext4") == 0) {
            snprintf(command, sizeof(command), "mkfs.ext4 -F %s", part->device);
        } else if (strcmp(part->filesystem, "btrfs") == 0) {
            snprintf(command, sizeof(command), "mkfs.btrfs -f %s", part->device);
        } else if (strcmp(part->filesystem, "xfs") == 0) {
            snprintf(command, sizeof(command), "mkfs.xfs -f %s", part->device);
        } else if (strcmp(part->filesystem, "vfat") == 0) {
            snprintf(command, sizeof(command), "mkfs.vfat -F 32 %s", part->device);
        } else if (strcmp(part->filesystem, "swap") == 0) {
            snprintf(command, sizeof(command), "mkswap %s", part->device);
        } else {
            continue;
        }
        
        printf("포맷 중: %s (%s)\n", part->device, part->filesystem);
        if (system(command) != 0) {
            log_install_message("ERROR", "파티션 포맷 실패");
            return -1;
        }
    }
    
    update_progress(2, 40, "파티션 포맷 완료");
    log_install_message("INFO", "파티션 포맷 완료");
    return 0;
}

// 파일시스템 마운트
int mount_filesystems(void) {
    char command[512];
    
    update_progress(3, 50, "파일시스템 마운트 중...");
    
    // 루트 파티션 마운트
    for (int i = 0; i < g_config.partition_count; i++) {
        partition_t *part = &g_config.partitions[i];
        
        if (strlen(part->mount_point) > 0) {
            char mount_path[512];
            snprintf(mount_path, sizeof(mount_path), "%s%s", TEMP_MOUNT_PATH, part->mount_point);
            
            // 마운트 디렉토리 생성
            snprintf(command, sizeof(command), "mkdir -p %s", mount_path);
            system(command);
            
            // 마운트
            if (strcmp(part->filesystem, "swap") != 0) {
                snprintf(command, sizeof(command), "mount %s %s", part->device, mount_path);
                printf("마운트 중: %s -> %s\n", part->device, mount_path);
                if (system(command) != 0) {
                    log_install_message("ERROR", "파일시스템 마운트 실패");
                    return -1;
                }
            } else {
                snprintf(command, sizeof(command), "swapon %s", part->device);
                system(command);
            }
        }
    }
    
    update_progress(3, 60, "파일시스템 마운트 완료");
    log_install_message("INFO", "파일시스템 마운트 완료");
    return 0;
}

// 기본 시스템 설치
int install_base_system(void) {
    char command[512];
    
    update_progress(4, 70, "기본 시스템 설치 중...");
    
    // 패키지 설치
    snprintf(command, sizeof(command), "pacstrap -K %s base linux linux-firmware", TEMP_MOUNT_PATH);
    printf("기본 시스템 설치: %s\n", command);
    if (system(command) != 0) {
        log_install_message("ERROR", "기본 시스템 설치 실패");
        return -1;
    }
    
    // fstab 생성
    snprintf(command, sizeof(command), "genfstab -U %s >> %s/etc/fstab", TEMP_MOUNT_PATH, TEMP_MOUNT_PATH);
    system(command);
    
    update_progress(4, 80, "기본 시스템 설치 완료");
    log_install_message("INFO", "기본 시스템 설치 완료");
    return 0;
}

// 부트로더 설정
int configure_bootloader(void) {
    char command[512];
    
    update_progress(5, 85, "부트로더 설정 중...");
    
    if (strcmp(g_config.bootloader, "grub") == 0) {
        // GRUB 설치
        snprintf(command, sizeof(command), "arch-chroot %s pacman -S --noconfirm grub efibootmgr", TEMP_MOUNT_PATH);
        system(command);
        
        snprintf(command, sizeof(command), "arch-chroot %s grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB", TEMP_MOUNT_PATH);
        system(command);
        
        snprintf(command, sizeof(command), "arch-chroot %s grub-mkconfig -o /boot/grub/grub.cfg", TEMP_MOUNT_PATH);
        system(command);
    }
    
    update_progress(5, 90, "부트로더 설정 완료");
    log_install_message("INFO", "부트로더 설정 완료");
    return 0;
}

// 사용자 생성
int create_users(void) {
    char command[512];
    
    update_progress(6, 92, "사용자 생성 중...");
    
    for (int i = 0; i < g_config.user_count; i++) {
        user_t *user = &g_config.users[i];
        
        // 사용자 생성
        snprintf(command, sizeof(command), "arch-chroot %s useradd -m -s %s -u %d -g %d %s", 
                TEMP_MOUNT_PATH, user->shell, user->uid, user->gid, user->username);
        system(command);
        
        // 비밀번호 설정
        snprintf(command, sizeof(command), "echo '%s:%s' | arch-chroot %s chpasswd", 
                user->username, user->password, TEMP_MOUNT_PATH);
        system(command);
        
        // sudo 권한 설정
        if (user->sudo_access) {
            snprintf(command, sizeof(command), "echo '%s ALL=(ALL) ALL' >> %s/etc/sudoers", 
                    user->username, TEMP_MOUNT_PATH);
            system(command);
        }
    }
    
    update_progress(6, 94, "사용자 생성 완료");
    log_install_message("INFO", "사용자 생성 완료");
    return 0;
}

// 네트워크 설정
int configure_network(void) {
    char command[512];
    char config_file[512];
    FILE *fp;
    
    update_progress(7, 96, "네트워크 설정 중...");
    
    // 호스트네임 설정
    snprintf(command, sizeof(command), "echo %s > %s/etc/hostname", g_config.hostname, TEMP_MOUNT_PATH);
    system(command);
    
    // 네트워크 설정 파일 생성
    snprintf(config_file, sizeof(config_file), "%s/etc/systemd/network/10-static.network", TEMP_MOUNT_PATH);
    fp = fopen(config_file, "w");
    if (fp) {
        fprintf(fp, "[Match]\n");
        fprintf(fp, "Name=%s\n\n", g_config.network.interface);
        fprintf(fp, "[Network]\n");
        
        if (strcmp(g_config.network.method, "static") == 0) {
            fprintf(fp, "Address=%s/%s\n", g_config.network.ip_address, g_config.network.netmask);
            fprintf(fp, "Gateway=%s\n", g_config.network.gateway);
            fprintf(fp, "DNS=%s\n", g_config.network.dns);
        } else {
            fprintf(fp, "DHCP=yes\n");
        }
        
        fclose(fp);
    }
    
    update_progress(7, 98, "네트워크 설정 완료");
    log_install_message("INFO", "네트워크 설정 완료");
    return 0;
}

// 설치 마무리
int finalize_installation(void) {
    char command[512];
    
    update_progress(8, 99, "설치 마무리 중...");
    
    // 시스템 설정
    snprintf(command, sizeof(command), "arch-chroot %s ln -sf /usr/share/zoneinfo/%s /etc/localtime", 
            TEMP_MOUNT_PATH, g_config.timezone);
    system(command);
    
    snprintf(command, sizeof(command), "arch-chroot %s echo '%s.UTF-8 UTF-8' > /etc/locale.gen", 
            TEMP_MOUNT_PATH, g_config.locale);
    system(command);
    
    snprintf(command, sizeof(command), "arch-chroot %s locale-gen", TEMP_MOUNT_PATH);
    system(command);
    
    snprintf(command, sizeof(command), "arch-chroot %s echo 'LANG=%s.UTF-8' > /etc/locale.conf", 
            TEMP_MOUNT_PATH, g_config.locale);
    system(command);
    
    // 서비스 활성화
    snprintf(command, sizeof(command), "arch-chroot %s systemctl enable systemd-networkd", TEMP_MOUNT_PATH);
    system(command);
    
    if (g_config.enable_ssh) {
        snprintf(command, sizeof(command), "arch-chroot %s systemctl enable sshd", TEMP_MOUNT_PATH);
        system(command);
    }
    
    update_progress(8, 100, "설치 완료");
    log_install_message("INFO", "설치 완료");
    return 0;
}

// 설치 워커 스레드
void* install_worker(void *arg) {
    // 설치 단계 등록
    g_step_count = 0;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "디스크 파티셔닝");
    strcpy(g_steps[g_step_count].description, "디스크 파티션 생성 및 설정");
    g_steps[g_step_count].execute = partition_disk;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 60;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "파티션 포맷");
    strcpy(g_steps[g_step_count].description, "파티션 포맷 및 파일시스템 생성");
    g_steps[g_step_count].execute = format_partitions;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 30;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "파일시스템 마운트");
    strcpy(g_steps[g_step_count].description, "파일시스템 마운트");
    g_steps[g_step_count].execute = mount_filesystems;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 10;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "기본 시스템 설치");
    strcpy(g_steps[g_step_count].description, "기본 시스템 패키지 설치");
    g_steps[g_step_count].execute = install_base_system;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 300;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "부트로더 설정");
    strcpy(g_steps[g_step_count].description, "부트로더 설치 및 설정");
    g_steps[g_step_count].execute = configure_bootloader;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 60;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "사용자 생성");
    strcpy(g_steps[g_step_count].description, "시스템 사용자 생성");
    g_steps[g_step_count].execute = create_users;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 30;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "네트워크 설정");
    strcpy(g_steps[g_step_count].description, "네트워크 설정");
    g_steps[g_step_count].execute = configure_network;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 20;
    g_step_count++;
    
    g_steps[g_step_count].step_id = g_step_count;
    strcpy(g_steps[g_step_count].name, "설치 마무리");
    strcpy(g_steps[g_step_count].description, "시스템 설정 마무리");
    g_steps[g_step_count].execute = finalize_installation;
    g_steps[g_step_count].required = 1;
    g_steps[g_step_count].estimated_time = 40;
    g_step_count++;
    
    g_status.total_steps = g_step_count;
    
    // 설치 단계 실행
    for (int i = 0; i < g_step_count; i++) {
        g_status.current_step = i;
        g_steps[i].status = 1; // 실행 중
        
        printf("실행 중: %s\n", g_steps[i].name);
        
        int result = g_steps[i].execute(g_steps[i].data);
        
        if (result == 0) {
            g_steps[i].status = 2; // 완료
            printf("완료: %s\n", g_steps[i].name);
        } else {
            g_steps[i].status = -1; // 실패
            printf("실패: %s\n", g_steps[i].name);
            
            if (g_steps[i].required) {
                log_install_message("ERROR", "필수 설치 단계 실패");
                g_status.install_complete = -1;
                return NULL;
            }
        }
    }
    
    g_status.install_complete = 1;
    log_install_message("INFO", "설치 프로세스 완료");
    
    return NULL;
}

// 진행 상황 업데이트
void update_progress(int step, int percent, const char *message) {
    pthread_mutex_lock(&g_status.mutex);
    g_status.progress_percent = percent;
    strncpy(g_status.status_message, message, sizeof(g_status.status_message) - 1);
    
    if (g_main_win) {
        // ncurses 화면 업데이트
        wclear(g_main_win);
        mvwprintw(g_main_win, 1, 2, "설치 진행 상황: %d%%", percent);
        mvwprintw(g_main_win, 2, 2, "상태: %s", message);
        wrefresh(g_main_win);
    } else {
        // 콘솔 출력
        printf("\r[%d%%] %s", percent, message);
        fflush(stdout);
    }
    
    pthread_mutex_unlock(&g_status.mutex);
}

// 설치 로그 기록
int log_install_message(const char *level, const char *message) {
    time_t now;
    char timestamp[64];
    FILE *log_fp;
    
    time(&now);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
    
    log_fp = fopen(INSTALL_LOG_PATH, "a");
    if (log_fp) {
        fprintf(log_fp, "[%s] %s: %s\n", timestamp, level, message);
        fclose(log_fp);
    }
    
    printf("[%s] %s: %s\n", timestamp, level, message);
    return 0;
}

// 시스템 요구사항 검증
int verify_system_requirements(void) {
    FILE *fp;
    char buffer[1024];
    unsigned long long memory_mb = 0;
    int cpu_cores = 0;
    
    // 메모리 검증
    fp = fopen("/proc/meminfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "MemTotal:", 9) == 0) {
                sscanf(buffer + 9, "%llu", &memory_mb);
                memory_mb = memory_mb / 1024; // KB to MB
                break;
            }
        }
        fclose(fp);
    }
    
    // CPU 코어 수 검증
    fp = fopen("/proc/cpuinfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "processor", 9) == 0) {
                cpu_cores++;
            }
        }
        fclose(fp);
    }
    
    printf("시스템 요구사항 검증:\n");
    printf("  메모리: %llu MB (최소 2048 MB 필요)\n", memory_mb);
    printf("  CPU 코어: %d개 (최소 2개 필요)\n", cpu_cores);
    
    if (memory_mb < 2048) {
        printf("오류: 메모리가 부족합니다.\n");
        return -1;
    }
    
    if (cpu_cores < 2) {
        printf("오류: CPU 코어가 부족합니다.\n");
        return -1;
    }
    
    printf("시스템 요구사항 충족\n");
    return 0;
}
