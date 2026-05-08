/*
 * UnifiedArch OS Network Security Header
 * 네트워크 보안 기능을 위한 헤더 파일
 * 
 * 이 헤더는 다음 네트워크 보안 기능을 제공합니다:
 * - 방화벽 규칙 관리
 * - 침입 탐지 시스템
 * - VPN 연결 관리
 * - 네트워크 암호화
 * - 포트 스캐닝 방지
 * - DDoS 보호
 */

#ifndef UNIFIEDARCH_NETWORK_SECURITY_H
#define UNIFIEDARCH_NETWORK_SECURITY_H

#include <linux/types.h>
#include <linux/netfilter.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/icmp.h>
#include <linux/ipv6.h>
#include <linux/in.h>
#include <linux/socket.h>
#include <linux/atomic.h>
#include <linux/mutex.h>
#include <linux/list.h>

// 버전 정보
#define NETWORK_SECURITY_VERSION "1.0.0"
#define MAX_FIREWALL_RULES 1000
#define MAX_VPN_CONNECTIONS 10
#define MAX_INTRUSION_LOGS 5000

// 방화벽 규칙 타입
typedef enum {
    FIREWALL_RULE_ALLOW = 0,
    FIREWALL_RULE_DENY,
    FIREWALL_RULE_DROP,
    FIREWALL_RULE_REJECT,
    FIREWALL_RULE_LOG,
    FIREWALL_RULE_MAX
} firewall_rule_type_t;

// 프로토콜 타입
typedef enum {
    PROTO_TCP = IPPROTO_TCP,
    PROTO_UDP = IPPROTO_UDP,
    PROTO_ICMP = IPPROTO_ICMP,
    PROTO_ALL = 255
} protocol_type_t;

// 방화벽 규칙 구조체
struct firewall_rule {
    u32 id;
    char name[64];
    firewall_rule_type_t action;
    protocol_type_t protocol;
    __be32 src_ip;
    __be32 src_mask;
    __be32 dst_ip;
    __be32 dst_mask;
    __u16 src_port_start;
    __u16 src_port_end;
    __u16 dst_port_start;
    __u16 dst_port_end;
    bool enabled;
    u32 priority;
    unsigned long created_time;
    unsigned long hit_count;
    char description[256];
    struct list_head list;
};

// 침입 탐지 이벤트 타입
typedef enum {
    INTRUSION_PORT_SCAN = 0,
    INTRUSION_DOS_ATTACK,
    INTRUSION_BRUTE_FORCE,
    INTRUSION_SUSPICIOUS_TRAFFIC,
    INTRUSION_MALWARE_COMMUNICATION,
    INTRUSION_MAX
} intrusion_type_t;

// 침입 탐지 이벤트 구조체
struct intrusion_event {
    u32 id;
    intrusion_type_t type;
    u32 severity;  // 1-10
    __be32 src_ip;
    __be32 dst_ip;
    __u16 src_port;
    __u16 dst_port;
    protocol_type_t protocol;
    unsigned long timestamp;
    char description[256];
    char details[512];
    bool blocked;
    struct list_head list;
};

// VPN 연결 상태
typedef enum {
    VPN_DISCONNECTED = 0,
    VPN_CONNECTING,
    VPN_CONNECTED,
    VPN_DISCONNECTING,
    VPN_ERROR
} vpn_state_t;

// VPN 타입
typedef enum {
    VPN_OPENVPN = 0,
    VPN_IPSEC,
    VPN_WIREGUARD,
    VPN_SSTP,
    VPN_MAX
} vpn_type_t;

// VPN 연결 구조체
struct vpn_connection {
    u32 id;
    char name[64];
    vpn_type_t type;
    vpn_state_t state;
    char server_address[256];
    __u16 server_port;
    char username[64];
    char config_file[512];
    bool auto_connect;
    unsigned long connect_time;
    unsigned long bytes_sent;
    unsigned long bytes_received;
    struct list_head list;
};

// 네트워크 보안 통계
struct network_security_stats {
    atomic_t total_packets;
    atomic_t blocked_packets;
    atomic_t allowed_packets;
    atomic_t intrusion_events;
    atomic_t firewall_rules_active;
    atomic_t vpn_connections_active;
    unsigned long last_update;
};

// 네트워크 보안 관리자
struct network_security_manager {
    struct list_head firewall_rules;
    struct list_head intrusion_events;
    struct list_head vpn_connections;
    struct mutex firewall_mutex;
    struct mutex intrusion_mutex;
    struct mutex vpn_mutex;
    struct network_security_stats stats;
    
    // 설정
    bool firewall_enabled;
    bool intrusion_detection_enabled;
    bool auto_block_intrusions;
    bool log_all_packets;
    u32 max_intrusion_events;
    
    // 임계값
    u32 port_scan_threshold;      // 포트당 연결 수
    u32 dos_threshold;           // 초당 패킷 수
    u32 brute_force_threshold;    // 실패 로그인 시도
};

// 함수 선언

// 방화벽 관리
int network_security_init(void);
void network_security_cleanup(void);

int firewall_add_rule(struct firewall_rule *rule);
int firewall_remove_rule(u32 rule_id);
int firewall_enable_rule(u32 rule_id, bool enabled);
struct firewall_rule *firewall_get_rule(u32 rule_id);
int firewall_update_rule(u32 rule_id, struct firewall_rule *new_rule);
void firewall_list_rules(void);
int firewall_clear_rules(void);

// 패킷 필터링
int firewall_filter_packet(struct sk_buff *skb, struct net_device *in_dev,
                          struct net_device *out_dev);
bool firewall_should_block_packet(struct sk_buff *skb);
void firewall_update_stats(bool blocked, protocol_type_t proto);

// 침입 탐지
int intrusion_detection_init(void);
void intrusion_detection_cleanup(void);

int intrusion_log_event(intrusion_type_t type, u32 severity,
                       __be32 src_ip, __be32 dst_ip,
                       __u16 src_port, __u16 dst_port,
                       protocol_type_t protocol,
                       const char *description, const char *details);
int intrusion_block_ip(__be32 ip, u32 duration_seconds);
bool intrusion_is_ip_blocked(__be32 ip);
void intrusion_cleanup_old_events(void);

// VPN 관리
int vpn_add_connection(struct vpn_connection *conn);
int vpn_remove_connection(u32 conn_id);
int vpn_connect(u32 conn_id);
int vpn_disconnect(u32 conn_id);
struct vpn_connection *vpn_get_connection(u32 conn_id);
int vpn_update_connection(u32 conn_id, struct vpn_connection *new_conn);
void vpn_list_connections(void);

// 네트워크 암호화
int network_encrypt_packet(struct sk_buff *skb, u8 *key, u32 key_len);
int network_decrypt_packet(struct sk_buff *skb, u8 *key, u32 key_len);
int network_generate_key(u8 *key, u32 key_len);

// 보안 정책 관리
int security_policy_load(const char *policy_file);
int security_policy_save(const char *policy_file);
int security_policy_apply(void);
int security_policy_validate(void);

// 모니터링 및 통계
void network_security_update_stats(void);
struct network_security_stats *network_security_get_stats(void);
int network_security_export_stats(char *buffer, size_t buffer_size);

// 유틸리티 함수
const char *firewall_rule_type_to_string(firewall_rule_type_t type);
const char *protocol_type_to_string(protocol_type_t proto);
const char *intrusion_type_to_string(intrusion_type_t type);
const char *vpn_type_to_string(vpn_type_t type);
const char *vpn_state_to_string(vpn_state_t state);

u32 generate_rule_id(void);
u32 generate_event_id(void);
u32 generate_connection_id(void);

bool is_valid_ip(__be32 ip);
bool is_valid_port(__u16 port);
bool is_ip_in_network(__be32 ip, __be32 network, __be32 mask);
bool port_in_range(__u16 port, __u16 start, __u16 end);

// 디버깅 함수
#ifdef CONFIG_DEBUG_FS
int network_security_debug_init(void);
void network_security_debug_cleanup(void);
#endif

// proc 파일 시스템 인터페이스
int network_security_proc_init(void);
void network_security_proc_cleanup(void);

// sysfs 인터페이스
int network_security_sysfs_init(void);
void network_security_sysfs_cleanup(void);

// netfilter hook
#ifdef CONFIG_NETFILTER
int network_security_netfilter_init(void);
void network_security_netfilter_cleanup(void);
#endif

// 상수 정의
#define DEFAULT_PORT_SCAN_THRESHOLD 50
#define DEFAULT_DOS_THRESHOLD 1000
#define DEFAULT_BRUTE_FORCE_THRESHOLD 10
#define DEFAULT_MAX_INTRUSION_EVENTS 5000

#define FIREWALL_CHAIN_INPUT "INPUT"
#define FIREWALL_CHAIN_OUTPUT "OUTPUT"
#define FIREWALL_CHAIN_FORWARD "FORWARD"

#define VPN_CONFIG_DIR "/etc/unifiedarch/vpn"
#define FIREWALL_CONFIG_DIR "/etc/unifiedarch/firewall"
#define SECURITY_LOG_DIR "/var/log/unifiedarch/security"

// 에러 코드
#define NETWORK_SECURITY_SUCCESS 0
#define NETWORK_SECURITY_ERROR -1
#define NETWORK_SECURITY_INVALID_PARAM -2
#define NETWORK_SECURITY_NO_MEMORY -3
#define NETWORK_SECURITY_NOT_FOUND -4
#define NETWORK_SECURITY_ALREADY_EXISTS -5
#define NETWORK_SECURITY_PERMISSION_DENIED -6
#define NETWORK_SECURITY_SYSTEM_ERROR -7

#endif /* UNIFIEDARCH_NETWORK_SECURITY_H */
