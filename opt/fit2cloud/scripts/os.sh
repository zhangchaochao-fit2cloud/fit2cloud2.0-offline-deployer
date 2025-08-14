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
        return
    fi

    if systemctl is-active firewalld >/dev/null 2>&1; then
        log_info_inline "打开防火墙端口 $port ..."
        if ! firewall-cmd --list-ports | grep -qw "${port}/tcp"; then
            firewall-cmd --zone=public --add-port=${port}/tcp --permanent >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            systemctl restart docker >/dev/null 2>&1
        fi
        log_ok
    fi
}

# 端口检测
check_port(){
    local port=$1
    local record=0
    if [[ -z "$port" ]]; then
        return
    fi

    log_info_inline "端口 $port 检测 ..."
    if command -v lsof >/dev/null 2>&1; then
        record=$(lsof -iTCP:"$port" -sTCP:LISTEN | wc -l)
    elif command -v netstat >/dev/null 2>&1; then
        record=$(netstat -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    elif command -v ss >/dev/null 2>&1; then
        record=$(ss -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    else
        log_step_error "未检测到 lsof、netstat 或 ss 命令，端口检测跳过"
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
    print_subtitle "root 用户检测 ..."
    if [[ "$(id -u)" == 0 ]]; then
        log_ok
        return 0
    else
        log_step_error "请使用 root 用户执行安装脚本"
        return 1
    fi
}

# 操作系统检测
check_os() {
    local record=0
    log_info_inline "操作系统检测..."
    # Redhat
    if [[ -f /etc/redhat-release ]]; then
        local redhat_version=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
        local major_version=${redhat_version%%.*}
        if [[ "$major_version" =~ ^(7|8)$ ]]; then
            log_ok
            return 0
        else
            log_step_error "仅支持 CentOS 7.x/8.x, RHEL 7.x/8.x"
            return 1
        fi
    fi

    # Kylin
    if [[ -f /etc/kylin-release ]]; then
        log_ok
    fi

    # Other
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release

        if [[ "$ID" == "ubuntu" ]]; then
            local ubuntu_version=${VERSION_ID%%.*}
            if [[ "$ubuntu_version" =~ ^(20|22|24)$ ]]; then
                log_ok
                return 0
            else
                color_msg "仅支持 Ubuntu 20/22/24"
                return 1
            fi
        fi

        if [[ "$ID" == "openEuler" ]]; then
            local euler_version=${VERSION_ID%%.*}
            if [[ "$euler_version" =~ ^(22|23)$ ]]; then
                log_ok
                return 0
            else
                log_step_error "仅支持 EulerOS 22/23"
                return 1
            fi
        fi
        log_step_error "不支持的操作系统"
        return 1
    fi
        log_step_error "无法识别操作系统"
        return 1
}


# 服务器架构检测
check_arch() {
    log_info_inline "服务器架构检测..."
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
        return 0
        log_ok
    else
        log_step_error "架构必须是 x86_64 或 aarch64"
        return 1
    fi
}


# CPU检测
check_cpu() {
    log_info_inline "CPU检测..."
    arch=$(uname -m)
    cpu_count=$(grep -c ^processor /proc/cpuinfo)
    if (( cpu_count < 4 )); then
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
    if (( mem_total_kb < 16000000 )); then
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
    # 获取安装路径所在磁盘剩余空间(kb)
    disk_avail_kb=$(df -Pk "$CE_INSTALL_PATH" | awk 'NR==2 {print $4}')
    if (( disk_avail_kb < 200000000 )); then
        log_step_warn "剩余空间小于 200G，建议至少 200G"
        return 1
    else
        log_ok
        return 0
    fi
}

}