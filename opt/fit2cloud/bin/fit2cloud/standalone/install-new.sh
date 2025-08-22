#!/bin/bash

#================================================================
# FIT2CLOUD 云管平台 3.0 安装脚本
#================================================================
# 作者: zhangchaochao
# 版本: 3.0
# 描述: 自动化安装 FIT2CLOUD 云管平台的离线部署脚本
#================================================================
# set -ex

# 获取脚本所在目录
readonly BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_LOG="/tmp/fit2cloud-install.log"

# 引入工具函数库
source "$BASE_DIR/../fit2cloud/scripts/common.sh"
source "$BASE_DIR/../fit2cloud/scripts/os.sh"
source "$BASE_DIR/../fit2cloud/scripts/minio.sh"


SYSTEM_NAME="FIT2CLOUD 云管平台 3.0"
VERSION_INFO=`cat ../fit2cloud/conf/version`
SYSTEM_IPS=$(get_system_ip)

# Docker 镜像目录
DOCKER_IMAGE_DIR="$BASE_DIR/../docker-images"
# 扩展包目录
EXTENSIONS_DIR="$BASE_DIR/../extensions"

# 操作系统
OS=$(get_os)
OS_VERSION=$(get_os_version)

# 显示帮助信息
show_help() {
    cat << EOF
Fit2Cloud 2.0 安装脚本

用法: $0 [选项]

选项:
    -p, --install-path <路径>     指定安装路径 (默认: /opt)
    -d, --docker-path <路径>      指定 Docker 路径 (默认: /opt/fit2cloud/docker)
    -m, --minio-port <端口>       指定 MinIO 端口 (默认: 9001)
    -i, --install-minio <true/false> 是否安装 MinIO (默认: true)
    -s, --silent                  静默模式安装
    -c, --config-file <文件>      指定配置文件 (默认: install.env)
    -e, --env-file <文件>         指定环境变量文件
    -f, --force                   强制安装
    -q, --quiet                   静默输出
    -h, --help                    显示帮助信息

环境变量:
    INSTALL_PATH                  安装路径
    DOCKER_PATH                   Docker 路径
    MINIO_PORT                    MinIO 端口
    INSTALL_MINIO                 是否安装 MinIO
    SILENT_MODE                   静默模式
    CONFIG_FILE                   配置文件路径

配置文件格式 (install.env):
    INSTALL_PATH=/opt
    DOCKER_PATH=/opt/fit2cloud/docker
    MINIO_PORT=9001
    INSTALL_MINIO=true
    SILENT_MODE=false
    MINIO_ENDPOINT=http://10.1.13.111:9001
    MINIO_ACCESS_KEY=your_access_key
    MINIO_SECRET_KEY=your_secret_key
    MINIO_BUCKET=default

示例:
    # 使用默认配置安装
    $0

    # 指定安装路径
    $0 -p /usr/local/fit2cloud

    # 静默模式安装
    $0 -s

    # 使用配置文件
    $0 -c my-config.env

    # 使用环境变量
    INSTALL_PATH=/opt/fit2cloud $0

    # 不安装 MinIO，使用外部存储
    $0 -i false -e external-storage.env
EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--install-path)
                INSTALL_PATH="$2"
                shift 2
                ;;
            -d|--docker-path)
                DOCKER_PATH="$2"
                shift 2
                ;;
            -m|--minio-port)
                MINIO_PORT="$2"
                shift 2
                ;;
            -i|--install-minio)
                INSTALL_MINIO="$2"
                shift 2
                ;;
            -s|--silent)
                SILENT_MODE="true"
                shift
                ;;
            -c|--config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -e|--env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 配置访问地址
config_cmp_address() {

    SYSTEM_IPS_NUM=($SYSTEM_IPS)
    # 默认IP
    default_ip_addr="${SYSTEM_IPS_NUM[0]}"

    if [ ${#SYSTEM_IPS_NUM[@]} -gt 1 ]; then
        choice_default_ip=$(read_with_default "2. 默认访问IP："${default_ip_addr}"，确认？[y/n] " "y")
        echo -e "${choice_default_ip}\n"
        if [[ "$choice_default_ip" =~ ^[Nn]$ ]]; then
            echo -e "存在多个网卡 IP："
            for i in "${nums[@]}"; do
                echo "    $i"
            done
            read -p "请输入访问IP，按 Enter 确认：" ip_addr
            if [[ $ip_addr == https://* ]]; then
              ip_addr=${ip_addr: 8}
            fi
            if [[ $ip_addr == http://* ]]; then
              ip_addr=${ip_addr: 7}
            fi

            #如果未输入则取第一个
            if [ -z "$ip_addr" ]; then
              ip_addr=${SYSTEM_IPS_NUM[0]}
            fi
        else
            ip_addr=$choice_default_ip
        fi
        echo -e "服务访问IP: $ip_addr\n"
    elif [ ${#SYSTEM_IPS_NUM[@]} -eq 1 ]; then
        ip_addr=$default_ip_addr
        echo -e "2. 服务访问IP: $ip_addr\n"
    else
        read -p "没有查询到网卡 IP，请输入一个云管访问地址的 IP 或域名（可留空）：" ip_addr
        echo -e "2. 服务访问IP: $ip_addr\n"
    fi

    set_env_value CE_ACCESS_IP "$ip_addr"

    choice_default_protocol=$(read_with_default "3. 默认访问协议：http，确认？[y/n] " "y")
    echo -e "${choice_default_protocol}\n"

    if [[ "$choice_default_protocol" =~ ^[Nn]$ ]]; then
        access_protocol="https"
    else
        access_protocol="http"
    fi

    set_env_value CE_ACCESS_PROTOCOL "$access_protocol"

    echo -e "后续可在【管理中心-系统设置-系统参数】中搜索 fit2cloud.cmp.address 对访问地址进行管理\n"
}

# 配置安装路径
config_installer_path() {
    log_title_info "CloudExplorer"
    local installer_path=$(get_env_value CE_INSTALL_PATH)
    # 读取用户输入
    ce_tmp_path=$(read_with_default "1. 安装路径" "${installer_path}")
    echo -e "安装路径: $ce_tmp_path/fit2cloud\n"
    # 修改 fit2cloud.service 安装目录
    sed -i 's#^f2c_install_dir=".*"#f2c_install_dir="'"$ce_tmp_path"'"#g' fit2cloud.service

    installer_path=$ce_tmp_path
    mkdir -p $installer_path

    # 设置新的安装路径到 .env 文件中
    set_env_value CE_INSTALL_PATH $installer_path

    # 配置服务
    config_cmp_address
}

# 配置 MinIO
config_installer_minio() {
    install_minio
}

# 检查环境
check_prerequisites() {
    print_subtitle "安装配置向导..."
    # 检查安装路径
    config_installer_path
    # 安装 MinIO
    config_installer_minio
}

pre_install_check() {
    print_subtitle "检查系统要求..."

    exit_code=0
    skip_warning_code=0

    for fn in check_root check_os check_arch check_docker; do
        $fn || exit_code=1
    done

    for fn in check_cpu check_memory check_disk; do
        $fn || skip_warning_code=1
    done

    if [ $exit_code -ne 0 ]; then
        log_step_error "安装环境检测未通过，请查阅上述环境检测结果"
        exit 1
    fi

    if [ $skip_warning_code -ne 0 ]; then
        echo -e "\n"
        skip_warning=$(read_with_default "环境检测异常，机器配置建议不能低于 4C 16G 200G。是否跳过? [y/n]: " "y")
        if [[ ${skip_warning:-y} == "n" ]]; then
            log_step_error "安装环境检测未通过，请查阅上述环境检测结果"
            exit 1
        fi
    fi
    echo -e "\n"
    log_step_success "${SYSTEM_NAME} 安装环境检测已通过，开始安装"
}

# 开放端口
open_cmp_port() {
    local compose_ports=$(get_all_ports)

    for compose_port in ${compose_ports}; do
        open_port $compose_port
    done
}

# 配置 CMP
install_cmp() {
    print_title "配置 FIT2CLOUD 服务"

    # 开放端口
    open_cmp_port

    local installer_path=$(get_env_value CE_INSTALL_PATH)

    # 配置服务
    log_info_inline "配置服务"
    cp -rp ../fit2cloud $installer_path
    rm -rf $installer_path/fit2cloud/bin/fit2cloud
    chmod -R 777 $installer_path/fit2cloud/data
    chmod -R 777 $installer_path/fit2cloud/sftp
    chmod -R 777 $installer_path/fit2cloud/conf/rabbitmq
    chmod -R 777 $installer_path/fit2cloud/logs/rabbitmq
    chmod 644 $installer_path/fit2cloud/conf/mysql/my.cnf
    \cp fit2cloud.service /etc/init.d/fit2cloud
    chmod a+x /etc/init.d/fit2cloud
    \cp f2cctl /usr/bin/f2cctl
    chmod a+x /usr/bin/f2cctl
    log_ok

    log_info_inline "开机自启"

    # 开机自启
    if [[ $OS_VERSION == 7 || $OS == "kylin" ]]; then
        chkconfig --add fit2cloud
        fit2cloud_service=$(grep "service fit2cloud start" /etc/rc.d/rc.local | wc -l)
        if [[ "$fit2cloud_service" -eq 0 ]]; then
            echo "sleep 10" >> /etc/rc.d/rc.local
            echo "service fit2cloud start" >> /etc/rc.d/rc.local
        fi
        chmod +x /etc/rc.d/rc.local
    log_ok
    elif [[ $OS_VERSION  =~ ^(20|22|24) ]]; then
        if [[ -f /etc/init.d/fit2cloud ]]; then
            chmod +x /etc/init.d/fit2cloud
        else
            log_step_error "/etc/init.d/fit2cloud script not found."
            exit 1
        fi
        log_ok
    else
        log_step_success "跳过"
    fi

    log_info_inline "重启 Docker"
    systemctl restart docker
    log_ok
}

# 启动 CMP
start_cmp() {
    print_title "启动 FIT2CLOUD 服务"
    log_info_inline "等待服务启动..."
    if [[ $OS_VERSION == 7 || $OS == "kylin" ]]; then
        service fit2cloud start >> $INSTALL_LOG 2>&1
        log_ok
    elif [[ $OS_VERSION  =~ ^(20|22|24) ]]; then
        /etc/init.d/fit2cloud start >> $INSTALL_LOG 2>&1
        log_step_success "OK 使用/etc/init.d/fit2cloud [status | start | stop] 来进行服务管理"
    else
        log_step_error "未找到此操作系统的启动命令, 请手动重启"
    fi
}

# 安装扩展包
install_extensions() {
    if [ ! -d $EXTENSIONS_DIR ];then
        return
    fi
    extensions=$(ls -1 "$EXTENSIONS_DIR")
    extensions_num=($(ls -1 "$EXTENSIONS_DIR"))
    if [ ${#extensions_num[@]} -eq 0 ]; then
      return
    fi
    print_title "安装扩展模块"
    while 'true';do
        starting_num=$(service fit2cloud status | grep starting | wc -l)
        if [ "$starting_num" -eq 0 ];then
            for i in ${extensions[@]} ; do
                choice_install_extension=$(read_with_default "是否安装扩展模块 ${i}? [y/n] " "n")
                if [[ "$choice_install_extension" =~ ^[Yy]$ ]]; then
                    /bin/f2cctl install-module $i
                fi
            done
            break
        else
            echo -e "等待服务启动...\n"
            sleep 10
        fi
    done
}

# 安装
install() {
  # 安装 docker
  install_docker
  # 加载镜像
  load_images "$DOCKER_IMAGE_DIR"
  # 安装服务
  install_cmp
  # 启动服务
  start_cmp
  # 安装扩展模块
  install_extensions
}

# 结束提示
show_end_tip() {
    local ip=$(get_env_value CE_ACCESS_IP)
    local protocol=$(get_env_value CE_ACCESS_PROTOCOL)
    local port=$(get_env_value CE_ACCESS_PORT)
    echo
    echo
    log_success "${SYSTEM_NAME} 安装完成，请在服务完全启动后(大概需要等待5分钟左右)访问 $protocol://${ip}:${port} 来访问 FIT2CLOUD 云管平台"
    log_success "系统管理员初始登录信息："
    log_success "用户名：admin"
    log_success "密码：Password123@cmp"
    echo
}

# 输出
show_welcome() {
echo
cat << EOF
███████╗██╗████████╗██████╗  ██████╗██╗      ██████╗ ██╗   ██╗██████╗
██╔════╝██║╚══██╔══╝╚════██╗██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
█████╗  ██║   ██║    █████╔╝██║     ██║     ██║   ██║██║   ██║██║  ██║
██╔══╝  ██║   ██║   ██╔═══╝ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║     ██║   ██║   ███████╗╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
╚═╝     ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝
EOF
    print_title "开始安装 ${SYSTEM_NAME}"
}

# 主函数
main() {

    # 解析参数
    parse_args "$@"

    show_welcome
    # 检查系统
    pre_install_check
    # 配置
    check_prerequisites
    # 安装
    install
    # 结束提示
    show_end_tip
}

# 执行主函数
main "$@"

