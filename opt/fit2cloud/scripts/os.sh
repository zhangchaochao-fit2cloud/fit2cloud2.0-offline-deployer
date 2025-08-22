#!/bin/bash

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# compose 目录
COMPOSE_DIR="$SCRIPT_DIR/.."
EXT_COMPOSE_DIR="$SCRIPT_DIR/../external-compose"

# env 环境变量文件
ENV_FILE="$SCRIPT_DIR/../.env"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/docker.sh"

# 打开防火墙端口，参数：端口号
open_port() {
    local port=$1
    if [[ -z "$port" ]]; then
        return 0
    fi

    if ! systemctl status firewalld >/dev/null 2>&1; then
        return 0
    fi
    log_info_inline "开放端口 $port ..."
    if ! firewall-cmd --list-all | grep -w ports | grep -w "$port" >/dev/null; then
        firewall-cmd --zone=public --add-port=${port}/tcp --permanent >/dev/null
        firewall-cmd --reload >/dev/null
        systemctl restart docker >/dev/null 2>&1
    fi
    log_ok
}

# 端口检测
check_port(){
    local port=$1
    local record=0
    if [[ -z "$port" ]]; then
        return 0
    fi

    log_info_inline "端口 $port 检测 ..."
    if cmd_exists lsof; then
        record=$(lsof -iTCP:"$port" -sTCP:LISTEN | wc -l)
    elif cmd_exists netstat; then
        record=$(netstat -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    elif cmd_exists ss; then
        record=$(ss -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    else
        log_step_error "未找到端口检测工具(lsof/netstat/ss)，跳过检测"
        return 0
    fi

    if [[ $record -eq 0 ]]; then
        log_ok
        return 0
    else
        log_step_error "[被占用]"
        return 1
    fi
}

check_service_port(){
    fit2cloudPorts=`grep -A 1 "ports:$" ../fit2cloud/docker-compose.yml | grep "\-.*:" | awk -F":" '{print $1}' | awk -F" " '{print $2}'`
    for fit2cloudPort in ${fit2cloudPorts}; do
      checkPort $fit2cloudPort
    done
}

# root 用户检测
check_root(){
    log_info_inline "root 用户检测..."
    if [[ $EUID -eq 0 ]]; then
        log_ok
        return 0
    else
        log_step_error "请使用 root 用户执行安装脚本"
        return 1
    fi
}

# 操作系统检测
get_os_version() {
    major_version="unknown"
    if [[ $os == "redhat" || $os == "centos" ]]; then
        version=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+')
        major_version=$(echo $version | awk -F. '{print $1}')
    elif [[ $os == "ubuntu" || $os == "openEuler" ]]; then
        source /etc/os-release
        version=$VERSION_ID
        major_version=$(echo $version | awk -F. '{print $1}')
    elif [[ $os == "kylin" ]]; then
        source /etc/os-release
        major_version=$VERSION_ID
    elif [[ ! $os == "unknown" ]]; then
        source /etc/os-release
        major_version=$VERSION_ID
    fi
    echo $major_version
}

# 操作系统检测
get_os() {
    os="unknown"

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu)
                os="ubuntu"
                ;;
            openEuler)
                os="openEuler"
                ;;
            kylin)
                os="kylin"
                ;;
            centos)
                os="centos"
                ;;
            *)
                os="$ID"
                ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        os="redhat"
    fi

    echo $os
}

# 操作系统检测
check_os() {
    local record=0
    log_info_inline "操作系统检测..."

    os=$(get_os)
    version=$(get_os_version)

    local supported=false

    if [[ $os == "redhat" || $os == "centos" ]]; then
        if [[ $version  =~ ^(7|8) ]]; then
            supported=true
        fi
    elif [[ $os == "ubuntu" ]]; then
        if [[ $version  =~ ^(20|22|24) ]]; then
            supported=true
        fi
    elif [[ $os == "openEuler" ]]; then
        if [[ $version =~ ^(22|23) ]]; then
            supported=true
        fi
    elif [[ $os == "kylin" ]]; then
        supported=true
    fi

    if $supported; then
        log_ok
        return 0
    else
        log_step_error "仅支持 CentOS 7.x/8.x, RHEL 7.x/8.x, Kylin, Ubuntu 20/22/24, openEuler 22/23"
        return 1
    fi
}


# 服务器架构检测
check_arch() {
    log_info_inline "服务器架构检测..."
    local arch=$(uname -m)
    if [[ $arch == "x86_64" ]] || [[ $arch == "aarch64" ]]; then
        log_ok
        return 0
    else
        log_step_error "架构必须是 x86_64 或 aarch64"
        return 1
    fi
}


# CPU检测
check_cpu() {
    log_info_inline "CPU 检测..."
    arch=$(uname -m)
    local cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
    if [[ $cores -lt 4 ]]; then
        log_step_warn "CPU 小于 4 核，建议至少 4 核"
        return 1
    else
        log_ok
        return 0
    fi
}

# 内存检测
check_memory() {
    log_info_inline "内存检测..."
    mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    if [[ $mem_kb -lt 16000000 ]]; then
        log_step_warn "内存小于 16G，建议至少 16G"
        return 1
    else
        log_ok
        return 0
    fi
}

# 磁盘空间检测
check_disk() {
    log_info_inline "磁盘空间检测..."
    local installer_path=$(get_env_value CE_INSTALL_PATH)
    # 获取安装路径所在磁盘剩余空间(kb)
    disk_avail_kb=$(df -Pk "$installer_path" | awk 'NR==2 {print $4}')
    if [[ $available_kb -lt 200000000 ]]; then
        log_step_warn "剩余空间小于 200G，建议至少 200G"
        return 1
    else
        log_ok
        return 0
    fi
}

