#!/usr/bin/env bash
#
# UnifiedArch OS 통합 archiso 프로필

iso_name="unifiedarch-unified"
iso_label="UNIFIEDARCH"
iso_publisher="UnifiedArch OS Project"
iso_application="UnifiedArch OS Unified Live/Install - All Variants"
iso_version="1.0.0"
install_dir="unifiedarch"
work_dir="/home/me/문서/os/build/unified-iso/work/archiso"
out_dir="/home/me/문서/os/build/unified-iso/out"
bootmodes=("bios" "uefi")
arch="x86_64"
pacman_conf="pacman.conf"
