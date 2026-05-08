/*
 * UnifiedArch OS Security Tools Header
 * 보안 도구 및 유틸리티를 위한 헤더 파일
 * 
 * 이 헤더는 다음 보안 기능을 제공합니다:
 * - 암호화 및 해시 함수
 * - 파일 무결성 검사
 * - 사용자 인증 시스템
 * - 접근 제어 관리
 * - 감사 로깅 시스템
 * - 보안 정책 관리
 */

#ifndef UNIFIEDARCH_SECURITY_TOOLS_H
#define UNIFIEDARCH_SECURITY_TOOLS_H

#include <linux/types.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/uaccess.h>
#include <linux/crypto.h>
#include <linux/scatterlist.h>
#include <linux/uuid.h>
#include <linux/random.h>
#include <linux/mutex.h>
#include <linux/list.h>
#include <linux/atomic.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/time.h>

// 버전 정보
#define SECURITY_TOOLS_VERSION "1.0.0"
#define MAX_SECURITY_POLICIES 100
#define MAX_AUDIT_LOGS 10000
#define MAX_INTEGRITY_HASHES 5000
#define MAX_ENCRYPTION_KEYS 50

// 암호화 알고리즘 타입
typedef enum {
    CRYPTO_AES_256 = 0,
    CRYPTO_AES_128,
    CRYPTO_CHACHA20,
    CRYPTO_BLOWFISH,
    CRYPTO_TWOFISH,
    CRYPTO_MAX
} crypto_algorithm_t;

// 해시 알고리즘 타입
typedef enum {
    HASH_SHA256 = 0,
    HASH_SHA512,
    HASH_SHA3_256,
    HASH_SHA3_512,
    HASH_BLAKE2B,
    HASH_MD5,  // 비권장 (하위 호환성용)
    HASH_MAX
} hash_algorithm_t;

// 인증 타입
typedef enum {
    AUTH_PASSWORD = 0,
    AUTH_PUBLIC_KEY,
    AUTH_TWO_FACTOR,
    AUTH_BIOMETRIC,
    AUTH_CERTIFICATE,
    AUTH_MAX
} auth_type_t;

// 접근 제어 타입
typedef enum {
    ACL_READ = 0x01,
    ACL_WRITE = 0x02,
    ACL_EXECUTE = 0x04,
    ACL_DELETE = 0x08,
    ACL_ADMIN = 0x80,
    ACL_ALL = 0xFF
} access_control_type_t;

// 감사 이벤트 타입
typedef enum {
    AUDIT_LOGIN = 0,
    AUDIT_LOGOUT,
    AUDIT_FILE_ACCESS,
    AUDIT_PERMISSION_CHANGE,
    AUDIT_SECURITY_POLICY_CHANGE,
    AUDIT_SYSTEM_CONFIG_CHANGE,
    AUDIT_CRYPTO_OPERATION,
    AUDIT_INTRUSION_ATTEMPT,
    AUDIT_MAX
} audit_event_type_t;

// 암호화 키 구조체
struct crypto_key {
    u32 id;
    char name[64];
    crypto_algorithm_t algorithm;
    u8 key_data[64];  // 최대 512비트 키
    u32 key_length;
    u8 iv[32];        // 초기화 벡터
    bool is_private;
    unsigned long created_time;
    unsigned long last_used;
    atomic_t usage_count;
    struct list_head list;
};

// 파일 무결성 해시 구조체
struct file_integrity_hash {
    char file_path[512];
    hash_algorithm_t algorithm;
    u8 hash[64];      // 최대 512비트 해시
    u32 hash_length;
    unsigned long calculated_time;
    bool is_valid;
    char signature[256];  // 디지털 서명
    struct list_head list;
};

// 보안 정책 구조체
struct security_policy {
    u32 id;
    char name[64];
    char description[256];
    u32 priority;
    bool enabled;
    unsigned long created_time;
    unsigned long last_modified;
    
    // 정책 규칙
    struct {
        bool require_encryption;
        bool require_integrity_check;
        bool require_authentication;
        bool audit_all_access;
        u32 min_password_length;
        u32 password_complexity;
        u32 session_timeout;
        u32 max_failed_attempts;
    } rules;
    
    struct list_head list;
};

// 감사 로그 구조체
struct audit_log {
    u32 id;
    audit_event_type_t event_type;
    u32 severity;  // 1-10
    uid_t uid;
    pid_t pid;
    char process_name[16];
    char resource_path[512];
    char description[256];
    char details[512];
    unsigned long timestamp;
    bool success;
    struct list_head list;
};

// 사용자 인증 정보 구조체
struct user_auth {
    uid_t uid;
    char username[64];
    auth_type_t auth_type;
    
    union {
        struct {
            char password_hash[256];
            char salt[32];
            u32 iterations;
        } password;
        
        struct {
            char public_key[1024];
            char private_key[2048];  // 암호화된 형태
        } key_pair;
        
        struct {
            char secret[128];
            char backup_codes[10][16];
        } two_factor;
        
        struct {
            char certificate[2048];
            char ca_certificate[1024];
        } certificate;
    } auth_data;
    
    unsigned long last_login;
    unsigned int failed_attempts;
    bool locked;
    struct list_head list;
};

// 접근 제어 목록 구조체
struct access_control_entry {
    uid_t uid;
    gid_t gid;
    char resource_path[512];
    u32 permissions;
    bool inherited;
    unsigned long created_time;
    struct list_head list;
};

// 보안 도구 관리자
struct security_tools_manager {
    struct list_head crypto_keys;
    struct list_head integrity_hashes;
    struct list_head security_policies;
    struct list_head audit_logs;
    struct list_head user_auths;
    struct list_head acl_entries;
    
    struct mutex crypto_mutex;
    struct mutex integrity_mutex;
    struct mutex policy_mutex;
    struct mutex audit_mutex;
    struct mutex auth_mutex;
    struct mutex acl_mutex;
    
    // 통계
    atomic_t total_encryptions;
    atomic_t total_decryptions;
    atomic_t total_hash_calculations;
    atomic_t total_auth_attempts;
    atomic_t total_audit_events;
    atomic_t failed_operations;
    
    // 설정
    bool encryption_enabled;
    bool integrity_check_enabled;
    bool authentication_enabled;
    bool audit_enabled;
    u32 max_audit_logs;
    u32 audit_retention_days;
};

// 함수 선언

// 초기화 및 정리
int security_tools_init(void);
void security_tools_cleanup(void);

// 암호화 기능
int crypto_generate_key(crypto_algorithm_t algorithm, u8 *key, u32 key_length);
int crypto_encrypt_data(const u8 *plaintext, u32 plain_len,
                       u8 *ciphertext, u32 *cipher_len,
                       const struct crypto_key *key);
int crypto_decrypt_data(const u8 *ciphertext, u32 cipher_len,
                       u8 *plaintext, u32 *plain_len,
                       const struct crypto_key *key);
int crypto_add_key(struct crypto_key *key);
int crypto_remove_key(u32 key_id);
struct crypto_key *crypto_get_key(u32 key_id);
int crypto_update_key(u32 key_id, struct crypto_key *new_key);

// 해시 기능
int hash_calculate(const u8 *data, u32 data_len,
                  u8 *hash, u32 *hash_len,
                  hash_algorithm_t algorithm);
int hash_file(const char *file_path,
              u8 *hash, u32 *hash_len,
              hash_algorithm_t algorithm);
int hash_string(const char *string,
                u8 *hash, u32 *hash_len,
                hash_algorithm_t algorithm);
int integrity_add_hash(const char *file_path, hash_algorithm_t algorithm);
int integrity_verify_file(const char *file_path);
int integrity_update_hash(const char *file_path);
int integrity_scan_directory(const char *directory_path);

// 사용자 인증
int auth_add_user(struct user_auth *user);
int auth_remove_user(uid_t uid);
int auth_authenticate(uid_t uid, const void *credentials, auth_type_t type);
int auth_change_password(uid_t uid, const char *old_password, const char *new_password);
int auth_set_two_factor(uid_t uid, const char *secret);
int auth_verify_two_factor(uid_t uid, const char *code);
int auth_lock_user(uid_t uid, bool lock);
struct user_auth *auth_get_user(uid_t uid);

// 접근 제어
int acl_add_entry(struct access_control_entry *entry);
int acl_remove_entry(uid_t uid, const char *resource_path);
int acl_check_permission(uid_t uid, const char *resource_path, u32 required_permission);
int acl_grant_permission(uid_t uid, const char *resource_path, u32 permissions);
int acl_revoke_permission(uid_t uid, const char *resource_path, u32 permissions);
int acl_list_permissions(uid_t uid, const char *resource_path);

// 감사 로깅
int audit_log_event(audit_event_type_t event_type, u32 severity,
                    uid_t uid, pid_t pid, const char *resource_path,
                    const char *description, const char *details,
                    bool success);
int audit_export_logs(const char *output_file);
int audit_clear_old_logs(u32 days);
int audit_search_logs(audit_event_type_t event_type, uid_t uid,
                      unsigned long start_time, unsigned long end_time,
                      struct audit_log *results, u32 max_results);

// 보안 정책 관리
int policy_add(struct security_policy *policy);
int policy_remove(u32 policy_id);
int policy_enable(u32 policy_id, bool enabled);
int policy_update(u32 policy_id, struct security_policy *new_policy);
int policy_apply_all(void);
int policy_validate_all(void);
struct security_policy *policy_get(u32 policy_id);
bool policy_check_requirement(const char *requirement);

// 보안 유틸리티
int security_generate_random_bytes(u8 *buffer, u32 length);
int security_generate_uuid(uuid_t *uuid);
int security_compare_hashes(const u8 *hash1, const u8 *hash2, u32 length);
int security_base64_encode(const u8 *input, u32 input_len,
                          char *output, u32 *output_len);
int security_base64_decode(const char *input, u32 input_len,
                          u8 *output, u32 *output_len);

// 보안 검증
int security_verify_system_integrity(void);
int security_check_password_strength(const char *password);
int security_detect_rootkit(void);
int security_scan_malware(const char *directory_path);
int security_check_file_permissions(const char *file_path);

// 백업 및 복원
int security_backup_keys(const char *backup_file);
int security_restore_keys(const char *backup_file);
int security_export_policies(const char *export_file);
int security_import_policies(const char *import_file);

// 유틸리티 함수
const char *crypto_algorithm_to_string(crypto_algorithm_t algorithm);
const char *hash_algorithm_to_string(hash_algorithm_t algorithm);
const char *auth_type_to_string(auth_type_t type);
const char *audit_event_to_string(audit_event_type_t event_type);

u32 generate_key_id(void);
u32 generate_policy_id(void);
u32 generate_audit_id(void);

bool is_secure_file(const char *file_path);
bool is_sensitive_path(const char *path);
bool has_valid_permissions(uid_t uid, const char *path, u32 required_perm);

// 디버깅 함수
#ifdef CONFIG_DEBUG_FS
int security_tools_debug_init(void);
void security_tools_debug_cleanup(void);
#endif

// proc 파일 시스템 인터페이스
int security_tools_proc_init(void);
void security_tools_proc_cleanup(void);

// sysfs 인터페이스
int security_tools_sysfs_init(void);
void security_tools_sysfs_cleanup(void);

// 상수 정의
#define DEFAULT_MIN_PASSWORD_LENGTH 8
#define DEFAULT_PASSWORD_COMPLEXITY 3
#define DEFAULT_SESSION_TIMEOUT 3600  // 1시간
#define DEFAULT_MAX_FAILED_ATTEMPTS 3
#define DEFAULT_AUDIT_RETENTION_DAYS 90

#define SECURITY_CONFIG_DIR "/etc/unifiedarch/security"
#define SECURITY_KEY_DIR "/etc/unifiedarch/keys"
#define SECURITY_LOG_DIR "/var/log/unifiedarch/security"
#define INTEGRITY_DB_PATH "/var/lib/unifiedarch/integrity.db"

// 에러 코드
#define SECURITY_TOOLS_SUCCESS 0
#define SECURITY_TOOLS_ERROR -1
#define SECURITY_TOOLS_INVALID_PARAM -2
#define SECURITY_TOOLS_NO_MEMORY -3
#define SECURITY_TOOLS_NOT_FOUND -4
#define SECURITY_TOOLS_ALREADY_EXISTS -5
#define SECURITY_TOOLS_PERMISSION_DENIED -6
#define SECURITY_TOOLS_CRYPTO_ERROR -7
#define SECURITY_TOOLS_AUTH_FAILED -8
#define SECURITY_TOOLS_INTEGRITY_FAILED -9
#define SECURITY_TOOLS_POLICY_VIOLATION -10

// 보안 레벨 정의
#define SECURITY_LEVEL_LOW 1
#define SECURITY_LEVEL_MEDIUM 5
#define SECURITY_LEVEL_HIGH 8
#define SECURITY_LEVEL_CRITICAL 10

// 암호화 키 길이
#define AES_256_KEY_SIZE 32
#define AES_128_KEY_SIZE 16
#define CHACHA20_KEY_SIZE 32
#define BLOWFISH_KEY_SIZE 56
#define TWOFISH_KEY_SIZE 32

// 해시 길이
#define SHA256_HASH_SIZE 32
#define SHA512_HASH_SIZE 64
#define SHA3_256_HASH_SIZE 32
#define SHA3_512_HASH_SIZE 64
#define BLAKE2B_HASH_SIZE 64
#define MD5_HASH_SIZE 16

#endif /* UNIFIEDARCH_SECURITY_TOOLS_H */
