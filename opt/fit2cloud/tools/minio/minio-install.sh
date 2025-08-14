#!/bin/bash

# =============================================================================
# MinIO 安装脚本
# 支持环境变量配置
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# 引入工具函数库
source "$PROJECT_ROOT/bin/utils.sh"

# =============================================================================
# 环境变量配置
# =============================================================================

# 基础配置
F2C_INSTALL_DIR=$(get_env "F2C_INSTALL_DIR" "/opt")
MINIO_PARENT_FOLDER=$(get_env "MINIO_PARENT_FOLDER" "$F2C_INSTALL_DIR/fit2cloud")
MINIO_FOLDER=$(get_env "MINIO_FOLDER" "$MINIO_PARENT_FOLDER/minio")
MINIO_PORT=$(get_env "MINIO_PORT" "9001")
MINIO_IP=$(get_env "MINIO_IP" "$(hostname -I | awk '{print $1}')")

# 镜像配置
MINIO_DOCKER_IMAGE=$(get_env "MINIO_DOCKER_IMAGE" "registry.fit2cloud.com/north/minio:latest")
MINIO_DOCKER_COMPOSE=$(get_env "MINIO_DOCKER_COMPOSE" "$MINIO_PARENT_FOLDER/external-compose/minio-compose.yml")

# 配置
CONFIG_FILE=$(get_env "CONFIG_FILE" "$MINIO_PARENT_FOLDER/conf/fit2cloud.properties")

# =============================================================================
# 函数定义
# =============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
MinIO 安装脚本

用法: $0 [选项]

选项:
    -h, --help          显示此帮助信息
    -d, --dir DIR       MinIO 工作目录 (默认: $MINIO_PARENT_FOLDER)
    -p, --port PORT     MinIO 端口 (默认: $MINIO_PORT)

环境变量:
    所有选项都可以通过环境变量设置，例如:
    MINIO_PORT=9002 $0
    MINIO_FOLDER=/data/minio $0

示例:
    # 基本安装
    $0

    # 指定端口
    $0 -p 9002

    # 指定目录
    $0 -d /data/fit2cloud
EOF
}

# 解析命令行参数
parse_args() {
    ARGS=$(getopt -o hd:p: --long help,dir:,port: -- "$@")
    if test $? != 0; then
        log_error "参数解析失败，请检查参数格式"
        show_help
        exit 1
    fi
    
    eval set -- "$ARGS"
    while true; do
        case "$1" in
            -d|--dir)
                MINIO_PARENT_FOLDER="$2"
                MINIO_FOLDER="$2/minio"
                shift 2
                ;;
            -p|--port)
                MINIO_PORT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查 Docker 环境
check_docker_environment() {
    print_title "检查 Docker 环境"
    
    # 检查 Docker 服务状态
    local docker_status=$(systemctl is-active docker)
    
    if [[ "$docker_status" != "active" ]]; then
        log_info "Docker 未启动，正在启动 Docker..."
        docker_start
        
        # 再次检查 Docker 服务状态
        docker_status=$(systemctl is-active docker)
        if [[ "$docker_status" == "active" ]]; then
            log_info "Docker 已成功启动"
        else
            log_error "Docker 启动失败，请检查系统日志"
            exit 1
        fi
    else
        log_info "Docker 已经在运行"
    fi
}

# 检查 MinIO 镜像
check_minio_image() {
    print_title "检查 MinIO 镜像"
    
    log_info "检查 MinIO 镜像: $MINIO_DOCKER_IMAGE"
    
    local minio_image_count=$(docker images | grep "$MINIO_DOCKER_IMAGE" | wc -l)
    if [[ "$minio_image_count" -eq "0" ]]; then
        log_info "MinIO 镜像不存在，开始加载..."
        
        local minio_tar="$SCRIPT_DIR/minio.tar"
        if [[ -f "$minio_tar" ]]; then
            docker load -q -i "$minio_tar"
            log_info "MinIO 镜像加载完成"
        else
            log_error "MinIO 镜像文件不存在: $minio_tar"
            exit 1
        fi
    else
        log_info "MinIO 镜像已存在"
    fi
}

# 准备 MinIO 目录
prepare_minio_directories() {
    print_title "准备 MinIO 目录"
    
    safe_mkdir "$MINIO_FOLDER"
    
    # 移动 .minio.sys 目录
    local source_sys_dir="$PROJECT_ROOT/data/minio/.minio.sys"
    if [[ -d "$source_sys_dir" ]]; then
        mv "$source_sys_dir" "$MINIO_FOLDER/"
        log_info "MinIO 系统目录移动完成"
    fi
    
    log_info "MinIO 目录准备完成: $MINIO_FOLDER"
}

# 配置 MinIO
configure_minio() {
    print_title "配置 MinIO"
    
    log_info "MinIO 配置信息："
    log_info "  运行端口: $MINIO_PORT"
    log_info "  日志目录: $MINIO_FOLDER/log"
    log_info "  文件目录: $MINIO_FOLDER"
    
    # 检查 docker-compose 文件
    if [[ ! -f "$MINIO_DOCKER_COMPOSE" ]]; then
        log_error "Docker Compose 文件不存在: $MINIO_DOCKER_COMPOSE"
        exit 1
    fi
    
    # 替换配置文件中的变量
    sed -i "s#9001#$MINIO_PORT#g" "$MINIO_DOCKER_COMPOSE"
    sed -i "s#minio_folder#$MINIO_FOLDER#g" "$MINIO_DOCKER_COMPOSE"
    sed -i "s#minio_docker_image#$MINIO_DOCKER_IMAGE#g" "$MINIO_DOCKER_COMPOSE"
    
    log_info "MinIO 配置完成"
}

# 启动 MinIO 服务
start_minio_service() {
    print_title "启动 MinIO 服务"
    
    log_info "启动 MinIO 服务..."
    
    # 使用 docker-compose 启动服务
    docker_compose_up "$MINIO_DOCKER_COMPOSE" "minio"
    
    # 创建启动脚本
    local start_script="$SCRIPT_DIR/minio-start.sh"
    echo "docker-compose -f $MINIO_DOCKER_COMPOSE up -d --no-recreate minio" > "$start_script"
    chmod +x "$start_script"
    
    log_info "MinIO 服务启动完成"
}

# 配置 MinIO 到 Fit2Cloud
configure_minio_to_fit2cloud() {
    print_title "配置 MinIO 到 Fit2Cloud"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Fit2Cloud 配置文件不存在: $CONFIG_FILE"
        return 0
    fi
    
    # 添加 MinIO 配置到 Fit2Cloud
    echo "" >> "$CONFIG_FILE"
    echo "minio.endpoint=http://$MINIO_IP:9000" >> "$CONFIG_FILE"
    echo "minio.accessKey=gzD4Mt5YSA1KQr1XnxSZ" >> "$CONFIG_FILE"
    echo "minio.secretKey=JQ1z9O5rcGZx1xsUjpadaRy0jQKdB56lGs3vDbEX" >> "$CONFIG_FILE"
    echo "minio.bucket.default=default" >> "$CONFIG_FILE"
    
    log_info "MinIO 配置已写入 Fit2Cloud 配置文件"
    log_info "可在管理中心/系统设置/系统参数中搜索 minio 进行管理"
}

# 检查 MinIO 服务状态
check_minio_status() {
    print_title "检查 MinIO 服务状态"
    
    # 等待服务启动
    sleep 5
    
    # 检查容器状态
    local container_name="minio"
    if docker ps | grep -q "$container_name"; then
        log_info "MinIO 容器运行正常"
        
        # 检查端口监听
        if check_port "$MINIO_PORT"; then
            log_info "MinIO 端口 $MINIO_PORT 监听正常"
        else
            log_warn "MinIO 端口 $MINIO_PORT 未监听，请检查服务状态"
        fi
    else
        log_error "MinIO 容器未运行"
        exit 1
    fi
}

# 显示安装完成信息
show_completion_info() {
    print_title "MinIO 安装完成"
    
    echo "*********************************************************************************************************************************"
    echo -e "\tMinIO 服务器安装完成！"
    echo
    echo -e "\t访问地址: http://$MINIO_IP:$MINIO_PORT"
    echo -e "\t管理控制台: http://$MINIO_IP:9000"
    echo
    echo -e "\t默认访问凭证："
    echo -ne "\t    Access Key: "
    echo -e "${YELLOW}\tgzD4Mt5YSA1KQr1XnxSZ${NC}"
    echo -ne "\t    Secret Key: "
    echo -e "${YELLOW}\tJQ1z9O5rcGZx1xsUjpadaRy0jQKdB56lGs3vDbEX${NC}"
    echo "*********************************************************************************************************************************"
    echo
}

# 主安装流程
main_install() {
    log_info "开始安装 MinIO..."
    
    check_docker_environment
    check_minio_image
    prepare_minio_directories
    configure_minio
    start_minio_service
    configure_minio_to_fit2cloud
    check_minio_status
    show_completion_info
    
    log_info "MinIO 安装流程完成"
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 解析命令行参数
    parse_args "$@"
    
    # 显示安装信息
    print_title "MinIO 安装信息"
    log_info "MinIO 镜像: $MINIO_DOCKER_IMAGE"
    log_info "安装目录: $MINIO_FOLDER"
    log_info "运行端口: $MINIO_PORT"
    log_info "访问地址: http://$MINIO_IP:$MINIO_PORT"
    echo
    
    # 检查必需的环境
    check_required_commands "docker" "docker-compose" || {
        log_error "环境检查失败，请安装必需的工具"
        exit 1
    }
    
    # 执行安装
    main_install
}

# 执行主函数
main "$@"