#!/usr/bin/env bash
# UnifiedArch OS archiso profile definition
# archiso 프로필 정의 파일

iso_name="unifiedarch"
iso_label="UNIFIEDARCH_$(date +%Y%m)"
iso_publisher="UnifiedArch OS Project <https://unifiedarch.org>"
iso_application="UnifiedArch OS Live/Install System"
iso_version="$(date +%Y.%m.%d)"
install_dir="unifiedarch"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
grub_cfg=""
file_permissions=(
    ["/etc/shadow"]="0:0:600"
    ["/etc/gshadow"]="0:0:600"
    ["/etc/sudoers.d"]="0:0:750"
    ["/usr/local/bin/"]="0:0:755"
)
