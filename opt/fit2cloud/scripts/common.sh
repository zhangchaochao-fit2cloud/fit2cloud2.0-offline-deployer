#!/bin/bash

# =============================================================================
# Fit2Cloud 2.0 通用工具函数库
# =============================================================================

# 颜色定义
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m' # No Color

# =============================================================================
# 日志输出函数
# =============================================================================


function get_padding {
    export LC_ALL=en_US.UTF-8
    local msg=$1
    local total_width=70
    # 非中文数量
    len1=$(echo "$msg" | grep -o '[^一-龥]' | wc -l)
    # 中文数量
    len2=$(echo "$msg" | grep -o "[一-龥]" | wc -l)
    # 中文x2 + 英文
    length=$(( len1 + len2 * 2 ))
    # 计算出空格并填充
    printf -v padding '%*s' $(( total_width - length )) ''
}

log_info_inline() {
    local msg="$1"
    msg_length=${#msg}

    get_padding "$msg"
    echo -ne "${GREEN}[INFO] ${NC} $1 $padding"
}

log_step_info() {
    echo -e "${GREEN}$1${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO] ${NC}$1"
}

log_title_info() {
    echo -e "${GREEN}【$1】${NC}\n"
}

#log_warn_inline() {
#    echo -ne "${YELLOW}[WARN]${NC} $1"
#}

log_step_warn() {
    echo -e "${YELLOW}$1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] ${NC} $1"
}

log_step_error() {
    echo -e "${RED}$1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] ${NC} $1"
}

log_step_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}$1${NC}"
    fi
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG] ${NC} $1"
    fi
}

log_ok() {
    echo -e "${CYAN}OK${NC} $1"
}

log_step_error() {
    echo -e "${RED}$1${NC} "
}

log_error() {
    echo -e "${RED}[ERROR] ${NC} $1"
}

log_step_success() {
    echo -e "${CYAN}$1${NC} "
}

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

print_title() {
    echo -e "\n\n${CYAN}******************************\t $1 \t******************************${NC}\n"
}

print_subtitle() {
    echo -e "\n${BLUE}------------------\t $1 \t------------------${NC}\n"
}

# =============================================================================
# 环境变量处理函数
# =============================================================================

# 读取环境变量，支持默认值
get_env() {
    local var_name=$1
    local default_value=$2
    eval "echo \${$var_name:-$default_value}"
}

# 读取配置变量
get_env_value() {
    # 脚本目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local key="$1"
    local default_value="$2"
    # env 环境变量文件
    local env_file="${3:-$script_dir/../.env}"

    # 使用 grep 和 shell 字符串处理提取变量值（忽略注释和空行）
    local value
    value=$(grep -E "^$key=" "$env_file" | grep -v '^#' | head -n 1 | cut -d'=' -f2-)

    if [[ -n "$value" ]]; then
      echo "$value"
    else
      echo "$default_value"
    fi
}

# 修改配置变量
set_env_value() {
    # 脚本目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local key="$1"
    local new_value="$2"
    local env_file="${3:-$script_dir/../.env}"

    if grep -qE "^${key}=" "$env_file"; then
        sed -i.bak -E "s|^(${key}=).*|\1${new_value}|" "$env_file"
    else
        echo "${key}=${new_value}" >> "$env_file"
    fi
}

# 检查必需的环境变量
check_required_env() {
    local var_name=$1
    local value=$(get_env "$var_name")
    if [[ -z "$value" ]]; then
        log_error "必需的环境变量 $var_name 未设置"
        exit 1
    fi
    echo "$value"
}

# 导出环境变量到文件
export_env_to_file() {
    local file_path=$1
    local var_name=$2
    local var_value=$3
    echo "$var_name=$var_value" >> "$file_path"
}

# =============================================================================
# 通用函数
# =============================================================================

# 检查命令是否存在
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 获取系统IP地址
get_system_ip() {
    ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p'
}

# 安全执行命令
safe_execute() {
    local cmd="$1"
    local msg="$2"

    log_info_inline "$msg..."
    if ! eval "$cmd" >>"$INSTALL_LOG" 2>&1; then
        log_step_error "执行失败"
        return 1
    fi
    log_ok
    return 0
}


download_file() {
    local url="$1"
    local output="$2"
    # 默认使用 wget
    if cmd_exists wget; then
        # 测试 wget 是否支持 --show-progress
        if wget --help 2>&1 | grep -q -- '--show-progress'; then
            wget --quiet --show-progress --progress=bar:force -O "$output" "$url"
        else
            if cmd_exists curl; then
                echo "Downloading $output ..."
                if curl -L --progress-bar -o "$output" "$url"; then
                    echo "Download finished"
                else
                    echo "Download failed: $url"
                    exit 1
                fi
            else
                wget --quiet --progress=bar:force -O "$output" "$url"
            fi
        fi
    else
        echo "Error: neither wget nor curl is installed." >&2
        return 1
    fi
}

# =============================================================================
# Docker 相关函数
# =============================================================================

# 启动 Docker 服务
docker_start() {
    log_info "启动 Docker 服务..."
    if systemctl is-active --quiet docker; then
        log_info "Docker 服务已在运行"
    else
        systemctl start docker
        systemctl enable docker
        log_info "Docker 服务启动完成"
    fi
}

# 运行 Docker 容器
docker_run() {
    local image=$1
    local name=$2
    shift 2
    local args="$@"
    
    log_info "启动容器: $name (镜像: $image)"
    docker run --name "$name" $args "$image"
}

# 使用 docker-compose 启动服务
docker_compose_up() {
    local compose_file=$1
    local service_name=${2:-""}
    
    log_info "使用 docker-compose 启动服务: $compose_file"
    if [[ -n "$service_name" ]]; then
        docker-compose -f "$compose_file" up -d --no-recreate "$service_name"
    else
        docker-compose -f "$compose_file" up -d
    fi
}

# 检查容器健康状态
docker_check_health() {
    local container_name=$1
    local max_wait_time=${2:-120}
    local wait_interval=${3:-5}
    local elapsed_time=0
    
    log_info "等待容器 $container_name 健康状态..."
    
    while [[ "$elapsed_time" -lt "$max_wait_time" ]]; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)
        if [[ "$health_status" == "healthy" ]]; then
            log_info "容器 $container_name 已健康"
            return 0
        fi
        sleep "$wait_interval"
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    log_error "容器 $container_name 健康检查超时"
    return 1
}

# =============================================================================
# 端口检测函数
# =============================================================================

# 验证文件是否存在
check_number() {
    local number="$1"
    if [[ ! "$number" =~ ^[0-9]+$ ]]; then
      return 1
    fi

    return 0
}

# 检查端口是否被占用
check_port() {
    local port=$1
    local record=0
    local not_found_tool=0
    
    log_info_inline "检查端口 $port 占用..."

    if ! check_number $port; then
        log_step_error "必须为数字"
        return 1
    fi
    
    if cmd_exists lsof; then
        record=$(lsof -i:$port | grep LISTEN | wc -l)
    elif cmd_exists netstat; then
        record=$(netstat -nplt | awk -F' ' '{print $4}' | grep "^[[:graph:]]*:$port$" | wc -l)
    elif cmd_exists ss; then
        record=$(ss -nlt | awk -F' ' '{print $4}' | grep "^[[:graph:]]*:$port$" | wc -l)
    else
        not_found_tool=1
    fi
    
    if [[ "$record" -eq "0" ]]; then
        if [[ "$not_found_tool" -eq "1" ]]; then
            log_step_warn "未找到检测工具 (lsof/netstat/ss)，跳过端口检测"
            return 0
        fi
        log_ok
        return 0
    else
        log_step_error "已占用"
        return 1
    fi
}

# 检查端口并返回结果
check_port_with_result() {
    local port=$1
    local record=0
    
    if command -v lsof &> /dev/null; then
        record=$(lsof -i:$port | grep LISTEN | wc -l)
    elif command -v netstat &> /dev/null; then
        record=$(netstat -nplt | awk -F' ' '{print $4}' | grep "^[[:graph:]]*:$port$" | wc -l)
    elif command -v ss &> /dev/null; then
        record=$(ss -nlt | awk -F' ' '{print $4}' | grep "^[[:graph:]]*:$port$" | wc -l)
    fi
    
    echo "$record"
}

# =============================================================================
# 系统检测函数
# =============================================================================

# 获取本机IP地址
get_local_ip() {
    ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p'
}

# 获取所有网卡IP
get_all_ips() {
    ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p' | tr '\n' ' '
}

# =============================================================================
# 防火墙操作函数
# =============================================================================

# 开放防火墙端口
open_firewall_port() {
    local port=$1
    local protocol=${2:-"tcp"}
    
    log_info "开放防火墙端口: $port/$protocol"
    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$port/$protocol" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        log_info "防火墙端口开放成功"
    elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$port/$protocol" >/dev/null 2>&1
        log_info "UFW 端口开放成功"
    else
        log_warn "未检测到活跃的防火墙服务，请手动开放端口 $port"
    fi
}

# =============================================================================
# 服务管理函数
# =============================================================================

# 启动系统服务
start_service() {
    local service_name=$1
    log_info "启动服务: $service_name"
    
    if systemctl is-active --quiet "$service_name"; then
        log_info "服务 $service_name 已在运行"
    else
        systemctl start "$service_name"
        systemctl enable "$service_name"
        log_info "服务 $service_name 启动完成"
    fi
}

# 检查服务状态
check_service_status() {
    local service_name=$1
    local status=$(systemctl is-active "$service_name")
    
    if [[ "$status" == "active" ]]; then
        log_info "服务 $service_name 运行正常"
        return 0
    else
        log_error "服务 $service_name 状态异常: $status"
        return 1
    fi
}

# =============================================================================
# 中间件连接检测函数
# =============================================================================

# 检测 MySQL 连接
check_mysql_connection() {
    local host=${1:-"localhost"}
    local port=${2:-"3306"}
    local user=${3:-"root"}
    local password=${4:-""}
    
    log_info "检测 MySQL 连接: $host:$port"
    
    if command -v mysql &> /dev/null; then
        if [[ -n "$password" ]]; then
            mysql -h"$host" -P"$port" -u"$user" -p"$password" -e "SELECT 1;" >/dev/null 2>&1
        else
            mysql -h"$host" -P"$port" -u"$user" -e "SELECT 1;" >/dev/null 2>&1
        fi
        
        if [[ $? -eq 0 ]]; then
            log_info "MySQL 连接成功"
            return 0
        fi
    fi
    
    log_error "MySQL 连接失败"
    return 1
}

# 检测 Redis 连接
check_redis_connection() {
    local host=${1:-"localhost"}
    local port=${2:-"6379"}
    local password=${3:-""}
    
    log_info "检测 Redis 连接: $host:$port"
    
    if command -v redis-cli &> /dev/null; then
        if [[ -n "$password" ]]; then
            redis-cli -h "$host" -p "$port" -a "$password" ping >/dev/null 2>&1
        else
            redis-cli -h "$host" -p "$port" ping >/dev/null 2>&1
        fi
        
        if [[ $? -eq 0 ]]; then
            log_info "Redis 连接成功"
            return 0
        fi
    fi
    
    log_error "Redis 连接失败"
    return 1
}

# =============================================================================
# 配置生成函数
# =============================================================================

# 生成配置文件
generate_config() {
    local template_file=$1
    local output_file=$2
    shift 2
    local replacements="$@"
    
    log_info "生成配置文件: $output_file"
    
    if [[ -f "$template_file" ]]; then
        cp "$template_file" "$output_file"
        
        # 执行替换
        for replacement in $replacements; do
            local key=$(echo "$replacement" | cut -d'=' -f1)
            local value=$(echo "$replacement" | cut -d'=' -f2-)
            sed -i "s#${key}#${value}#g" "$output_file"
        done
        
        log_info "配置文件生成完成"
    else
        log_error "模板文件不存在: $template_file"
        return 1
    fi
}

# 验证文件是否存在
check_required_files() {
    local files="$@"
    local missing_files=""
    
    for file in $files; do
        if [[ ! -f "$file" ]]; then
            missing_files="$missing_files $file"
        fi
    done
    
    if [[ -n "$missing_files" ]]; then
        log_error "缺少必需的文件: $missing_files"
        return 1
    fi
    
    return 0
}

read_with_default() {
    local prompt="$1"
    local default="$2"
    local input

    if [[ "$SILENT_MODE" == "true" ]]; then
        # 静默模式直接返回默认值
        echo "$prompt [$default]: " >&2
        echo "$default"
        return
    fi
    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}