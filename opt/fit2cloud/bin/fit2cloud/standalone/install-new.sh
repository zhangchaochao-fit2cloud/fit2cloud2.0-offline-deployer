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
        installer_path="$ce_path"
        echo "使用自定义安装路径: $installer_path/fit2cloud"

        # 如果路径不存在，直接退出
        if [[ ! -d "$installer_path" ]]; then
          mkdir -p $installer_path
        fi

        # 设置新的安装路径到 .env 文件中
        set_env_value CE_INSTALL_PATH $installer_path
    fi
}

check_installer_minio() {
    read -p "是否安装 MinIO 服务器? [y/n](默认y): " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
      configure_external_minio
    else
      configure_local_minio
    fi
}

# 检查环境
check_prerequisites() {
    # 检查安装路径
    check_installer_path
    # 安装 MinIO
    check_installer_minio
}

check_system_requirements() {
    print_subtitle "检查系统要求..."
    # 遍历所有检测函数
    for fn in check_root check_os check_arch check_cpu check_memory check_disk check_docker; do
        $fn || exit_code=1
    done

    # 最终判断
    if [ $exit_code -ne 0 ]; then
        log_error "${SYSTEM_NAME} 安装环境检测未通过，请查阅上述环境检测结果"
        exit 1
    else
        log_success "${SYSTEM_NAME} 安装环境检测已通过，可以开始安装"
    fi
}

install() {
  # 安装 docker
  install_docker

  #

}


# 输出
echo_fit2cloud() {
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

    print_title "开始打包 Fit2Cloud 2.0..."

    # 检查前置条件
    check_prerequisites

    echo_fit2cloud

    # 检查系统要求
    check_system_requirements

    install
}

# 执行主函数
main "$@"

