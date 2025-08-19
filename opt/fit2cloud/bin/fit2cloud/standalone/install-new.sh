#!/bin/bash

#================================================================
# FIT2CLOUD 云管平台 3.0 安装脚本
#================================================================
# 作者: zhangchaochao
# 版本: 3.0
# 描述: 自动化安装 FIT2CLOUD 云管平台的离线部署脚本
#================================================================

# 获取脚本所在目录
readonly BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_LOG="/tmp/fit2cloud-install.log"

# 引入工具函数库
source "$BASE_DIR/scripts/common.sh"
source "$BASE_DIR/scripts/os.sh"


SYSTEM_NAME="FIT2CLOUD 云管平台 3.0"
VERSION_INFO=`cat ../fit2cloud/conf/version`
SYSTEM_IPS=$(get_system_ip)

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

check_installer_path() {
    local installer_path=$(get_env_value CE_INSTALL_PATH)
    # 读取用户输入
    read -p "CloudExplorer 将安装到：${installer_path}/fit2cloud，如需更改请输入自定义路径，否则按回车继续: " ce_tmp_path

    # 如果用户没输入路径，则使用默认
    if [[ -z "$ce_tmp_path" ]]; then
        echo "使用默认安装路径: $installer_path/fit2cloud"
    else
        installer_path="$ce_tmp_path"
        echo "使用自定义安装路径: $installer_path/fit2cloud"

        # 如果路径不存在，直接退出
        mkdir -p $installer_path

        # 设置新的安装路径到 .env 文件中
        set_env_value CE_INSTALL_PATH $installer_path
    fi
}

check_installer_minio() {
    install_minio
}

# 检查环境
check_prerequisites() {
    # 检查安装路径
    check_installer_path
    # 安装 MinIO
    check_installer_minio
}

pre_install_check() {
    print_title "$SYSTEM_NAME 安装环境检测"

    local checks=(
        check_root_user
        check_os_version
        check_architecture
        check_cpu
        check_memory
    )

    for check in "${checks[@]}"; do
        if ! $check; then
            VALIDATION_PASSED=0
        fi
    done

    # 磁盘空间检测需要安装路径
    check_disk_space "$installer_path"

    # Docker环境检测
    if ! check_docker; then
        VALIDATION_PASSED=0
    fi

    # 端口检测
    check_required_ports

    # 检测结果处理
    if [[ $VALIDATION_PASSED -eq 0 ]]; then
        print_color $COLOR_RED "\n${SYSTEM_NAME} 安装环境检测未通过，请查阅上述环境检测结果\n"
        exit 1
    fi

    if [[ $VALIDATION_WARNING -eq 0 ]]; then
        echo
        read -p "${SYSTEM_NAME} 安装环境检测异常，机器配置建议不能低于 4C 16G 200G。是否跳过? [y/n](默认y): " skip_warning
        if [[ ${skip_warning:-y} == "n" ]]; then
            print_color $COLOR_RED "\n${SYSTEM_NAME} 安装环境检测未通过\n"
            exit 1
        fi
    fi
}

pre_install_check() {
    print_subtitle "检查系统要求..."

    for fn in check_root check_os check_arch check_docker; do
        $fn || exit_code=1
    done

    for fn in check_cpu check_memory check_disk; do
        $fn || skip_warning_code=1
    done

    if [ $exit_code -ne 0 ]; then
        log_error "${SYSTEM_NAME} 安装环境检测未通过，请查阅上述环境检测结果"
        exit 1
    fi

    if [ $skip_warning_code -ne 0 ]; then
        read -p "${SYSTEM_NAME} 安装环境检测异常，机器配置建议不能低于 4C 16G 200G。是否跳过? [y/n](默认y): " skip_warning
        if [[ ${skip_warning:-y} == "n" ]]; then
            log_error "${SYSTEM_NAME} 安装环境检测未通过，请查阅上述环境检测结果"
            exit 1
        fi
        exit 1
    fi

    log_success "${SYSTEM_NAME} 安装环境检测已通过，可以开始安装"
}

# 开放端口
open_cmp_port() {
  local ce_access_port=$(get_env_value CE_ACCESS_PORT)
  open_port $ce_access_port
}

# 配置 CMP
config_cmp() {
    printTitle "配置 FIT2CLOUD 服务"

    # 开放端口
    open_cmp_port

    local installer_path=$(get_env_value CE_INSTALL_PATH)

    # 配置服务
    log_info_inline "配置服务"
    cp -rp ../fit2cloud $installer_path
    rm -rf $installer_path/fit2cloud/bin/fit2cloud
    chmod -R 777 $installer_path/fit2cloud/data
    chmod -R 777 $installer_path/fit2cloud/git
    chmod -R 777 $installer_path/fit2cloud/sftp
    chmod -R 777 $installer_path/fit2cloud/conf/rabbitmq
    chmod -R 777 $installer_path/fit2cloud/logs/rabbitmq
    chmod 644 $installer_path/fit2cloud/conf/my.cnf
    \cp fit2cloud.service /etc/init.d/fit2cloud
    chmod a+x /etc/init.d/fit2cloud
    \cp f2cctl /usr/bin/f2cctl
    chmod a+x /usr/bin/f2cctl
    log_ok

    log_info_inline "开机自启"
    os=$(get_os)
    os_version=$(get_os_version)

    # 开机自启
    if [[ $os_version == 7 || $os == "kylin" ]]; then
        chkconfig --add fit2cloud
        fit2cloud_service=$(grep "service fit2cloud start" /etc/rc.d/rc.local | wc -l)
        if [[ "$fit2cloud_service" -eq 0 ]]; then
            echo "sleep 10" >> /etc/rc.d/rc.local
            echo "service fit2cloud start" >> /etc/rc.d/rc.local
        fi
        chmod +x /etc/rc.d/rc.local
    log_ok
    elif [[ $os_version == 20 || $os_version == 22 || $os_version == 24 ]]; then
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

# 配置访问地址
config_cmp_address() {
    printTitle "配置云管服务器的访问地址"

    # 查询结果转数组
    nums=($SYSTEM_IPS)
    ip_addr="${nums[0]}"

    if [ ${#nums[@]} -gt 1 ]; then
        # 多个网卡 IP
        echo -e "存在多个网卡 IP："
        for i in "${nums[@]}"; do
            echo "    $i"
        done
        read -p "将自动设置云管访问地址为：${nums[0]}；是否修改？(y/n) " be_sure
        if [[ "$be_sure" == "y" ]]; then
            read -p "请输入云管访问地址，按 Enter 确认：" ip_addr
            ip_addr=$(clean_address "${ip_addr:-${nums[0]}}")
        fi
    elif [ ${#nums[@]} -eq 1 ]; then
        # 只有一个网卡 IP
        ip_addr="${nums[0]}"
        echo "    http://$ip_addr"
    else
        # 没有网卡 IP
        echo "没有查询到网卡 IP，请输入一个云管访问地址的 IP 或域名（可留空）。"
        read -p "之后可在【管理中心-系统设置-系统参数】维护，按 Enter 确认：" ip_addr
        ip_addr=$(clean_address "$ip_addr")
        [ -n "$ip_addr" ] && echo "    http://$ip_addr"
    fi

    # 写入配置文件（即使 ipAddr 为空也写，方便后续修改）
    write_config "$ip_addr"

    # 数据采集配置文件需要配置当前宿主机真实 IP（如需启用可解开注释）
    # sed -i "s@tcp://localip:2375@tcp://$ip_addr:2375@g" "$installerPath/fit2cloud/conf/telegraf.conf"

    echo "配置已写入，可在【管理中心-系统设置-系统参数】中搜索 fit2cloud.cmp.address 进行管理。"
    echo "配置云管服务器的访问地址结束。"
}

install() {
  # 安装 docker
  install_docker
  # 加载镜像
  load_images
  # 配置服务
  config_cmp
  # 配置服务
  config_cmp_address
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
    print_title "开始安装 ${SYSTEM_NAME}，版本 - $VERSION_INFO"
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

    install
}

# 执行主函数
main "$@"

