#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/common.sh"

check_os() {
    local os=$(get_os)
    local version=$(get_os_version)

    log_info "操作系统: $os $version"

    case "$os" in
        centos|rhel|rocky|alma|redhat)
            if [[ "$version" -lt 7 ]]; then
                log_error "不支持 $os $version，需要 7 或以上"
                return 1
            fi
            ;;
        ubuntu|debian)
            if [[ "$version" -lt 20 ]]; then
                log_error "不支持 $os $version，需要 20 或以上"
                return 1
            fi
            ;;
        openEuler|kylin)
            ;;
        *)
            log_warn "未经测试的操作系统: $os"
            ;;
    esac
    log_ok
}

check_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  log_info "架构: $arch (amd64)" ;;
        aarch64|arm64) log_info "架构: $arch (arm64)" ;;
        *)
            log_error "不支持的架构: $arch"
            return 1
            ;;
    esac
}

check_cpu() {
    local min_cores=${1:-4}
    local cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")
    log_info "CPU: ${cores} 核"
    if [[ "$cores" -lt "$min_cores" ]]; then
        log_warn "CPU 少于 ${min_cores} 核，建议至少 ${min_cores} 核"
    fi
}

check_memory() {
    local min_mb=${1:-16384}
    local mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
    local mem_total_mb=$((mem_total_kb / 1024))
    log_info "内存: ${mem_total_mb}MB"
    if [[ "$mem_total_mb" -lt "$min_mb" ]]; then
        log_warn "内存不足 ${min_mb}MB，建议至少 ${min_mb}MB"
    fi
}

check_disk() {
    local min_gb=${1:-200}
    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$SCRIPT_DIR/../.env")
    local disk_avail_kb=$(df -Pk "$installer_path" 2>/dev/null | awk 'NR==2 {print $4}')
    local disk_avail_gb=$((disk_avail_kb / 1024 / 1024))
    log_info "磁盘: ${disk_avail_gb}GB 可用 (路径: $installer_path)"
    if [[ -n "$disk_avail_gb" && "$disk_avail_gb" -lt "$min_gb" ]]; then
        log_warn "磁盘空间不足 ${min_gb}GB，建议至少 ${min_gb}GB"
    fi
}

check_system_all() {
    print_title "系统检查"

    if [[ "$(id -u)" -ne 0 ]]; then
        log_warn "建议使用 root 用户安装"
    fi

    check_os || return 1
    check_arch || return 1
    check_cpu
    check_memory
    check_disk

    log_success "系统检查完成"
}
