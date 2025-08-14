#!/bin/bash

# =============================================================================
# Fit2Cloud 2.0 安装脚本
# 支持环境变量配置和外部中间件
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 引入工具函数库
source "$SCRIPT_DIR/../bin/utils.sh"

# =============================================================================
# 环境变量配置
# =============================================================================

# 基础配置
INSTALL_DIR=$(get_env "INSTALL_DIR" "/opt/fit2cloud")
WORKSPACE=$(get_env "WORKSPACE" "$PROJECT_ROOT")
DEBUG=$(get_env "DEBUG" "false")

# 镜像配置
IMAGE_ADDRESS=$(get_env "IMAGE_ADDRESS" "registry.fit2cloud.com/north")
PLATFORM=$(get_env "PLATFORM" "amd64")

# 端口配置
CE_ACCESS_PORT=$(get_env "CE_ACCESS_PORT" "80")
MINIO_PORT=$(get_env "MINIO_PORT" "9001")
NGINX_PORT=$(get_env "NGINX_PORT" "6680")

# 外部中间件配置
MYSQL_HOST=$(get_env "MYSQL_HOST" "")
MYSQL_PORT=$(get_env "MYSQL_PORT" "3306")
MYSQL_USER=$(get_env "MYSQL_USER" "root")
MYSQL_PASSWORD=$(get_env "MYSQL_PASSWORD" "")
MYSQL_DATABASE=$(get_env "MYSQL_DATABASE" "fit2cloud")

REDIS_HOST=$(get_env "REDIS_HOST" "")
REDIS_PORT=$(get_env "REDIS_PORT" "6379")
REDIS_PASSWORD=$(get_env "REDIS_PASSWORD" "")

MINIO_ENDPOINT=$(get_env "MINIO_ENDPOINT" "")
MINIO_ACCESS_KEY=$(get_env "MINIO_ACCESS_KEY" "")
MINIO_SECRET_KEY=$(get_env "MINIO_SECRET_KEY" "")

# 安装选项
INSTALL_MINIO=$(get_env "INSTALL_MINIO" "true")
INSTALL_NGINX=$(get_env "INSTALL_NGINX" "false")
INSTALL_TELEGRAF=$(get_env "INSTALL_TELEGRAF" "true")
SILENT_MODE=$(get_env "SILENT_MODE" "false")

# =============================================================================
# 函数定义
# =============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
Fit2Cloud 2.0 安装脚本

用法: $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -s, --silent           静默安装模式
    -d, --dir DIR          安装目录 (默认: /opt/fit2cloud)
    -p, --platform PLAT    平台架构 (默认: amd64)
    --mysql-host HOST      MySQL 主机地址
    --mysql-port PORT      MySQL 端口 (默认: 3306)
    --mysql-user USER      MySQL 用户名 (默认: root)
    --mysql-password PASS  MySQL 密码
    --redis-host HOST      Redis 主机地址
    --redis-port PORT      Redis 端口 (默认: 6379)
    --minio-endpoint URL   MinIO 端点
    --no-minio            不安装 MinIO
    --no-telegraf         不安装 Telegraf

环境变量:
    所有选项都可以通过环境变量设置，例如:
    INSTALL_DIR=/opt/fit2cloud $0
    MYSQL_HOST=192.168.1.100 $0

示例:
    # 使用外部 MySQL 和 Redis
    MYSQL_HOST=192.168.1.100 MYSQL_PASSWORD=mypass REDIS_HOST=192.168.1.101 $0

    # 静默安装
    SILENT_MODE=true $0

    # 自定义安装目录
    INSTALL_DIR=/data/fit2cloud $0
EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--silent)
                SILENT_MODE="true"
                shift
                ;;
            -d|--dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -p|--platform)
                PLATFORM="$2"
                shift 2
                ;;
            --mysql-host)
                MYSQL_HOST="$2"
                shift 2
                ;;
            --mysql-port)
                MYSQL_PORT="$2"
                shift 2
                ;;
            --mysql-user)
                MYSQL_USER="$2"
                shift 2
                ;;
            --mysql-password)
                MYSQL_PASSWORD="$2"
                shift 2
                ;;
            --redis-host)
                REDIS_HOST="$2"
                shift 2
                ;;
            --redis-port)
                REDIS_PORT="$2"
                shift 2
                ;;
            --minio-endpoint)
                MINIO_ENDPOINT="$2"
                shift 2
                ;;
            --no-minio)
                INSTALL_MINIO="false"
                shift
                ;;
            --no-telegraf)
                INSTALL_TELEGRAF="false"
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 显示安装信息
show_install_info() {
    print_title "Fit2Cloud 2.0 安装信息"
    
    log_info "安装目录: $INSTALL_DIR"
    log_info "镜像地址: $IMAGE_ADDRESS"
    log_info "平台架构: $PLATFORM"
    log_info "访问端口: $CE_ACCESS_PORT"
    
    print_subtitle "中间件配置"
    
    if [[ -n "$MYSQL_HOST" ]]; then
        log_info "MySQL: $MYSQL_HOST:$MYSQL_PORT (外部)"
    else
        log_info "MySQL: 本地安装"
    fi
    
    if [[ -n "$REDIS_HOST" ]]; then
        log_info "Redis: $REDIS_HOST:$REDIS_PORT (外部)"
    else
        log_info "Redis: 本地安装"
    fi
    
    if [[ -n "$MINIO_ENDPOINT" ]]; then
        log_info "MinIO: $MINIO_ENDPOINT (外部)"
    elif [[ "$INSTALL_MINIO" == "true" ]]; then
        log_info "MinIO: 本地安装 (端口: $MINIO_PORT)"
    else
        log_info "MinIO: 不安装"
    fi
    
    if [[ "$INSTALL_TELEGRAF" == "true" ]]; then
        log_info "Telegraf: 安装"
    else
        log_info "Telegraf: 不安装"
    fi
    
    echo
}

# 环境检查
check_environment() {
    print_title "环境检查"
    
    # 检查操作系统
    local os=$(detect_os)
    log_info "操作系统: $os"
    
    # 检查 Docker
    docker_check || {
        log_error "Docker 环境检查失败"
        exit 1
    }
    
    # 检查 docker-compose
    docker_compose_check || {
        log_error "docker-compose 环境检查失败"
        exit 1
    }
    
    # 检查端口占用
    check_port "$CE_ACCESS_PORT" || {
        log_error "端口 $CE_ACCESS_PORT 已被占用"
        exit 1
    }
    
    if [[ "$INSTALL_MINIO" == "true" && -z "$MINIO_ENDPOINT" ]]; then
        check_port "$MINIO_PORT" || {
            log_error "端口 $MINIO_PORT 已被占用"
            exit 1
        }
    fi
    
    log_info "环境检查通过"
}

# 准备安装目录
prepare_directories() {
    print_title "准备安装目录"
    
    safe_mkdir "$INSTALL_DIR"
    safe_mkdir "$INSTALL_DIR/conf"
    safe_mkdir "$INSTALL_DIR/logs"
    safe_mkdir "$INSTALL_DIR/data"
    safe_mkdir "$INSTALL_DIR/scripts"
    
    log_info "安装目录准备完成"
}

# 复制文件
copy_files() {
    print_title "复制安装文件"
    
    # 复制配置文件
    if [[ -d "$PROJECT_ROOT/opt/fit2cloud/conf" ]]; then
        cp -r "$PROJECT_ROOT/opt/fit2cloud/conf"/* "$INSTALL_DIR/conf/"
        log_info "配置文件复制完成"
    fi
    
    # 复制脚本文件
    if [[ -d "$PROJECT_ROOT/opt/fit2cloud/bin" ]]; then
        cp -r "$PROJECT_ROOT/opt/fit2cloud/bin" "$INSTALL_DIR/"
        log_info "脚本文件复制完成"
    fi
    
    # 复制 docker-compose 文件
    if [[ -d "$PROJECT_ROOT/opt/fit2cloud/external-compose" ]]; then
        cp -r "$PROJECT_ROOT/opt/fit2cloud/external-compose" "$INSTALL_DIR/"
        log_info "Docker Compose 文件复制完成"
    fi
    
    # 复制工具文件
    if [[ -d "$PROJECT_ROOT/opt/fit2cloud/tools" ]]; then
        cp -r "$PROJECT_ROOT/opt/fit2cloud/tools" "$INSTALL_DIR/"
        log_info "工具文件复制完成"
    fi
}

# 配置环境变量
configure_environment() {
    print_title "配置环境变量"
    
    local env_file="$INSTALL_DIR/.env"
    
    # 创建环境变量文件
    cat > "$env_file" << EOF
# Fit2Cloud 2.0 环境变量配置
IMAGE_ADDRESS=$IMAGE_ADDRESS
PLATFORM=$PLATFORM
CE_ACCESS_PORT=$CE_ACCESS_PORT

# 外部中间件配置
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=$MYSQL_PORT
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE

REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD

MINIO_ENDPOINT=$MINIO_ENDPOINT
MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY
MINIO_SECRET_KEY=$MINIO_SECRET_KEY

# 安装选项
INSTALL_MINIO=$INSTALL_MINIO
INSTALL_NGINX=$INSTALL_NGINX
INSTALL_TELEGRAF=$INSTALL_TELEGRAF
EOF
    
    log_info "环境变量配置完成: $env_file"
}

# 配置外部中间件
configure_external_middleware() {
    print_title "配置外部中间件"
    
    local config_file="$INSTALL_DIR/conf/fit2cloud.properties"
    
    # 配置 MySQL
    if [[ -n "$MYSQL_HOST" ]]; then
        log_info "配置外部 MySQL: $MYSQL_HOST:$MYSQL_PORT"
        echo "spring.datasource.url=jdbc:mysql://$MYSQL_HOST:$MYSQL_PORT/$MYSQL_DATABASE?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai" >> "$config_file"
        echo "spring.datasource.username=$MYSQL_USER" >> "$config_file"
        if [[ -n "$MYSQL_PASSWORD" ]]; then
            echo "spring.datasource.password=$MYSQL_PASSWORD" >> "$config_file"
        fi
    fi
    
    # 配置 Redis
    if [[ -n "$REDIS_HOST" ]]; then
        log_info "配置外部 Redis: $REDIS_HOST:$REDIS_PORT"
        echo "spring.redis.host=$REDIS_HOST" >> "$config_file"
        echo "spring.redis.port=$REDIS_PORT" >> "$config_file"
        if [[ -n "$REDIS_PASSWORD" ]]; then
            echo "spring.redis.password=$REDIS_PASSWORD" >> "$config_file"
        fi
    fi
    
    # 配置 MinIO
    if [[ -n "$MINIO_ENDPOINT" ]]; then
        log_info "配置外部 MinIO: $MINIO_ENDPOINT"
        echo "minio.endpoint=$MINIO_ENDPOINT" >> "$config_file"
        if [[ -n "$MINIO_ACCESS_KEY" ]]; then
            echo "minio.accessKey=$MINIO_ACCESS_KEY" >> "$config_file"
        fi
        if [[ -n "$MINIO_SECRET_KEY" ]]; then
            echo "minio.secretKey=$MINIO_SECRET_KEY" >> "$config_file"
        fi
    fi
    
    log_info "外部中间件配置完成"
}

# 安装 MinIO
install_minio() {
    if [[ "$INSTALL_MINIO" != "true" || -n "$MINIO_ENDPOINT" ]]; then
        return 0
    fi
    
    print_title "安装 MinIO"
    
    local minio_script="$INSTALL_DIR/tools/minio/minio-install.sh"
    if [[ -f "$minio_script" ]]; then
        cd "$(dirname "$minio_script")"
        bash "$minio_script" -d "$INSTALL_DIR" -p "$MINIO_PORT"
        log_info "MinIO 安装完成"
    else
        log_warn "MinIO 安装脚本不存在，跳过安装"
    fi
}

# 安装 Telegraf
install_telegraf() {
    if [[ "$INSTALL_TELEGRAF" != "true" ]]; then
        return 0
    fi
    
    print_title "安装 Telegraf"
    
    local telegraf_script="$INSTALL_DIR/tools/telegraf/telegraf-install.sh"
    if [[ -f "$telegraf_script" ]]; then
        cd "$(dirname "$telegraf_script")"
        bash "$telegraf_script"
        log_info "Telegraf 安装完成"
    else
        log_warn "Telegraf 安装脚本不存在，跳过安装"
    fi
}

# 启动服务
start_services() {
    print_title "启动 Fit2Cloud 服务"
    
    cd "$INSTALL_DIR"
    
    # 动态生成 compose 文件组合
    source "$INSTALL_DIR/tools/docker/compose-generate.sh"
    log_info "docker-compose 启动参数: $COMPOSE_FILES"
    
    # 使用 docker-compose 启动服务
    docker-compose $COMPOSE_FILES up -d
    log_info "Fit2Cloud 服务启动完成"
}

# 配置访问地址
configure_access_address() {
    print_title "配置访问地址"
    
    local ip_addr=$(get_local_ip)
    local config_file="$INSTALL_DIR/conf/fit2cloud.properties"
    
    if [[ -n "$ip_addr" ]]; then
        echo "fit2cloud.cmp.address=http://$ip_addr" >> "$config_file"
        log_info "访问地址配置完成: http://$ip_addr"
    else
        log_warn "无法获取本机IP地址，请手动配置访问地址"
    fi
}

# 安装完成提示
show_completion_info() {
    print_title "安装完成"
    
    local ip_addr=$(get_local_ip)
    
    echo "*********************************************************************************************************************************"
    echo -e "\tFit2Cloud 2.0 安装完成！"
    echo
    if [[ -n "$ip_addr" ]]; then
        echo -e "\t请在服务完全启动后(大约需要等待5分钟)访问: http://$ip_addr"
    else
        echo -e "\t请在服务完全启动后(大约需要等待5分钟)访问系统"
    fi
    echo
    echo -e "\t系统管理员初始登录信息："
    echo -ne "\t    用户名："
    echo -e "${YELLOW}\tadmin${NC}"
    echo -ne "\t    密码："
    echo -e "${YELLOW}\tPassword123@cmp${NC}"
    echo "*********************************************************************************************************************************"
    echo
}

# 静默安装模式
silent_install() {
    log_info "开始静默安装..."
    
    check_environment
    prepare_directories
    copy_files
    configure_environment
    configure_external_middleware
    install_minio
    install_telegraf
    start_services
    configure_access_address
    show_completion_info
}

# 交互式安装模式
interactive_install() {
    show_install_info
    
    if [[ "$SILENT_MODE" == "true" ]]; then
        silent_install
        return
    fi
    
    # 确认安装
    echo
    read -p "是否继续安装？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    
    silent_install
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 解析命令行参数
    parse_args "$@"
    
    # 初始化环境
    init_environment
    
    # 开始安装
    interactive_install
}

# 执行主函数
main "$@" 