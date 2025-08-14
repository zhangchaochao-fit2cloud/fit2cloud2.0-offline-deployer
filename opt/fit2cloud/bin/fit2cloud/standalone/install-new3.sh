#!/bin/bash

#================================================================
# FIT2CLOUD 云管平台 3.0 安装脚本
#================================================================
# 作者: FIT2CLOUD 团队
# 版本: 3.0
# 描述: 自动化安装 FIT2CLOUD 云管平台的离线部署脚本
#================================================================

#---------------------------------------------------------------
# 全局配置
#---------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly INSTALL_LOG="/tmp/fit2cloud-install.log"
readonly SYSTEM_NAME="FIT2CLOUD 云管平台 3.0"

# 默认配置
DEFAULT_INSTALL_PATH="/opt"
DEFAULT_MINIO_PORT=9001
DOCKER_PATH_SUFFIX="fit2cloud/docker"
DOCKER_CONFIG_FOLDER="/etc/docker"
DOCKER_CONFIG_FILE="${DOCKER_CONFIG_FOLDER}/daemon.json"

# 颜色配置
readonly COLOR_RED=31
readonly COLOR_GREEN=32
readonly COLOR_YELLOW=33
readonly COLOR_BLUE=34

# 状态标志
VALIDATION_PASSED=1
VALIDATION_WARNING=1

#---------------------------------------------------------------
# 工具函数
#---------------------------------------------------------------

# 打印标题
print_title() {
    echo -e "\n\n**********\t ${1} \t**********\n"
}

# 打印子标题
print_subtitle() {
    echo -e "------\t \033[${COLOR_BLUE}m ${1} \033[0m \t------\n"
}

# 彩色输出
print_color() {
    echo -e "\033[$1m $2 \033[0m"
}

# 检查命令是否存在
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 获取系统IP地址
get_system_ip() {
    ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p'
}

# 检查端口占用情况
check_port() {
    local port=$1
    local check_type=${2:-"normal"}
    local record=0
    
    # 检测命令优先级: lsof > netstat > ss
    if cmd_exists lsof; then
        record=$(lsof -i:${port} 2>/dev/null | grep LISTEN | wc -l)
    elif cmd_exists netstat; then
        record=$(netstat -nplt 2>/dev/null | awk -F' ' '{print $4}' | grep ":${port}$" | wc -l)
    elif cmd_exists ss; then
        record=$(ss -nlt 2>/dev/null | awk -F' ' '{print $4}' | grep ":${port}$" | wc -l)
    else
        print_color $COLOR_RED "[WARNING] 未找到端口检测工具(lsof/netstat/ss)，跳过检测"
        return 0
    fi
    
    echo -ne "$port 端口 \t\t........................ "
    if [[ $record -eq 0 ]]; then
        print_color $COLOR_GREEN "[OK]"
    else
        [[ $check_type == "normal" ]] && VALIDATION_PASSED=0
        print_color $COLOR_RED "[被占用]"
        return 1
    fi
    return 0
}

# 检查MinIO端口
check_minio_port() {
    local port=$1
    if check_port "$port" "minio"; then
        return 0
    else
        return 1
    fi
}

# 开放防火墙端口
open_firewall_port() {
    local port=$1
    
    if ! systemctl status firewalld >/dev/null 2>&1; then
        return 0
    fi
    
    echo -ne "打开防火墙端口${port} \t\t........................ "
    
    if ! firewall-cmd --list-all | grep -w ports | grep -w "$port" >/dev/null; then
        firewall-cmd --zone=public --add-port="${port}/tcp" --permanent >/dev/null
        firewall-cmd --reload >/dev/null
        systemctl restart docker >/dev/null 2>&1
    fi
    
    print_color $COLOR_GREEN "[OK]"
}

# 获取Docker存储目录
get_docker_dir() {
    docker info 2>/dev/null | grep "Docker Root Dir" | awk -F ': ' '{print $2}'
}

# 安全执行命令
safe_execute() {
    local cmd="$1"
    local error_msg="$2"
    
    if ! eval "$cmd" >>"$INSTALL_LOG" 2>&1; then
        print_color $COLOR_RED "执行失败: $error_msg"
        return 1
    fi
    return 0
}

#---------------------------------------------------------------
# 系统检测模块
#---------------------------------------------------------------

# 检测是否为root用户
check_root_user() {
    echo -ne "root 用户检测 \t\t........................ "
    if [[ $EUID -eq 0 ]]; then
        print_color $COLOR_GREEN "[OK]"
    else
        print_color $COLOR_RED "[ERROR] 请使用 root 用户执行安装脚本"
        return 1
    fi
    return 0
}

# 检测操作系统版本
check_os_version() {
    echo -ne "操作系统检测 \t\t........................ "
    
    local os_info=""
    local supported=false
    
    if [[ -f /etc/redhat-release ]]; then
        os_info=$(cat /etc/redhat-release)
        if [[ $os_info =~ CentOS\ ([7-8])\.* ]] || [[ $os_info =~ RHEL\ ([7-8])\.* ]]; then
            supported=true
        fi
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu)
                [[ $VERSION_ID =~ ^(20|22|24)\. ]] && supported=true
                ;;
            openEuler)
                [[ $VERSION_ID =~ ^(22|23)\. ]] && supported=true
                ;;
            *)
                supported=false
                ;;
        esac
    elif [[ -f /etc/kylin-release ]]; then
        supported=true
    fi
    
    if $supported; then
        print_color $COLOR_GREEN "[OK]"
    else
        print_color $COLOR_RED "[ERROR] 操作系统版本不符合要求"
        return 1
    fi
    return 0
}

# 检测系统架构
check_architecture() {
    echo -ne "服务器架构检测 \t\t........................ "
    local arch=$(uname -m)
    
    if [[ $arch == "x86_64" ]] || [[ $arch == "aarch64" ]]; then
        print_color $COLOR_GREEN "[OK]"
    else
        print_color $COLOR_RED "[ERROR] 架构必须是 x86_64 或 aarch64"
        return 1
    fi
    return 0
}

# 检测CPU核心数
check_cpu() {
    echo -ne "CPU检测 \t\t........................ "
    local cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
    
    if [[ $cores -lt 4 ]]; then
        print_color $COLOR_YELLOW "[WARNING] CPU 小于 4核，建议至少 4 核"
        VALIDATION_WARNING=0
    else
        print_color $COLOR_GREEN "[OK]"
    fi
}

# 检测内存大小
check_memory() {
    echo -ne "内存检测 \t\t........................ "
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    
    if [[ $mem_kb -lt 16000000 ]]; then
        print_color $COLOR_YELLOW "[WARNING] 内存小于 16G，建议至少 16G"
        VALIDATION_WARNING=0
    else
        print_color $COLOR_GREEN "[OK]"
    fi
}

# 检测磁盘空间
check_disk_space() {
    echo -ne "磁盘剩余空间检测 \t........................ "
    local install_path=$1
    local available_kb
    
    # 获取可用空间（KB）
    available_kb=$(df -P "$install_path" 2>/dev/null | awk 'NR==2 {print $4}' || df -P / 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [[ $available_kb -lt 200000000 ]]; then
        print_color $COLOR_YELLOW "[WARNING] 可用空间小于 200G，建议至少 200G"
        VALIDATION_WARNING=0
    else
        print_color $COLOR_GREEN "[OK]"
    fi
}

# 检测Docker环境
check_docker() {
    echo -ne "Docker 检测 \t\t........................ "
    
    if ! cmd_exists docker; then
        print_color $COLOR_GREEN "[OK] 未安装，将自动安装"
        return 0
    fi
    
    local version=$(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d'.' -f1)
    if [[ -z $version ]] || [[ $version -lt 18 ]]; then
        print_color $COLOR_RED "[ERROR] Docker 版本需要 18 以上"
        return 1
    fi
    
    local docker_dir=$(get_docker_dir)
    print_color $COLOR_GREEN "[OK] 存储目录：$docker_dir"
    
    echo -ne "docker-compose 检测 \t........................ "
    if ! cmd_exists docker-compose; then
        print_color $COLOR_RED "[ERROR] 未安装 docker-compose"
        return 1
    fi
    
    print_color $COLOR_GREEN "[OK]"
    return 0
}

# 检测所有必需的端口
check_required_ports() {
    local compose_file="${BASE_DIR}/fit2cloud/docker-compose.yml"
    
    if [[ -f $compose_file ]]; then
        local ports=$(grep -A 1 "ports:" "$compose_file" | grep "\-.*:" | awk -F":" '{print $1}' | awk '{print $NF}')
        for port in $ports; do
            check_port "$port"
        done
    fi
}

#---------------------------------------------------------------
# 配置模块
#---------------------------------------------------------------

# 更新安装路径配置
update_install_path() {
    local new_path=$1
    local files_to_update=(
        "../fit2cloud/tools/minio/minio-install.sh"
        "../fit2cloud/tools/docker/docker-install.sh"
        "f2cctl"
        "fit2cloud.service"
        "fit2cloud-install-extension.sh"
        "fit2cloud-upgrade-extension.sh"
        "upgrade.sh"
        "../fit2cloud/.env"
        "../fit2cloud/tools/telegraf/telegraf-install.sh"
    )
    
    for file in "${files_to_update[@]}"; do
        if [[ -f $file ]]; then
            case $file in
                *minio-install.sh)
                    sed -i "s#f2c_install_dir=\"/opt\"#f2c_install_dir=\"${new_path}\"#g" "$file"
                    ;;
                *docker-install.sh)
                    sed -i "s#dockerPath=\"/opt/fit2cloud/docker\"#dockerPath=\"${new_path}/fit2cloud/docker\"#g" "$file"
                    ;;
                f2cctl)
                    sed -i "s#work_dir=\"/opt/fit2cloud\"#work_dir=\"${new_path}/fit2cloud\"#g" "$file"
                    ;;
                fit2cloud.service)
                    sed -i "s#f2c_install_dir=\"/opt\"#f2c_install_dir=\"${new_path}\"#g" "$file"
                    ;;
                *extension.sh|upgrade.sh)
                    sed -i "s#fit2cloud_dir=\"/opt/fit2cloud\"#fit2cloud_dir=\"${new_path}/fit2cloud\"#g" "$file"
                    sed -i "s#installerPath=/opt#installerPath=\"${new_path}\"#g" "$file"
                    ;;
                *.env)
                    sed -i "s#installerPath=/opt#installerPath=${new_path}#g" "$file"
                    ;;
                *telegraf*)
                    sed -i "s#installerPath=/opt#installerPath=${new_path}#g" "$file"
                    ;;
            esac
        fi
    done
}

# 配置MinIO参数
configure_minio() {
    local config_file="${installer_path}/fit2cloud/conf/fit2cloud.properties"
    
    print_color $COLOR_YELLOW "配置MinIO参数..."
    
    read -p "仓库地址（如: http://10.1.13.111:9001）:" repo
    read -p "accessKey:" minio_ak
    read -p "secretKey:" minio_sk
    read -p "bucket:" bucket
    
    cat >> "$config_file" <<EOF

# MinIO配置
minio.endpoint=$repo
minio.accessKey=$minio_ak
minio.secretKey=$minio_sk
minio.bucket.default=$bucket
EOF
    
    print_color $COLOR_GREEN "MinIO配置已写入 $config_file"
}

# 配置云管访问地址
configure_cmp_address() {
    local ips=($1)
    local ip_addr
    
    if [[ ${#ips[@]} -gt 1 ]]; then
        echo "检测到多个网卡IP："
        printf '               %s\n' "${ips[@]}"
        
        read -p "将自动设置云管访问地址为：${ips[0]}，是否修改？(y/n): " modify_addr
        if [[ $modify_addr == "y" ]]; then
            read -p "请输入云管访问地址: " ip_addr
            ip_addr=${ip_addr#http://}
            ip_addr=${ip_addr#https://}
            [[ -z $ip_addr ]] && ip_addr=${ips[0]}
        else
            ip_addr=${ips[0]}
        fi
    else
        ip_addr=${ips[0]}
    fi
    
    echo "云管访问地址: http://$ip_addr"
    
    # 更新配置文件
    local config_file="${installer_path}/fit2cloud/conf/fit2cloud.properties"
    if [[ -f $config_file ]]; then
        sed -i "s#^fit2cloud\.endpoint=.*#fit2cloud.endpoint=http://${ip_addr}#g" "$config_file"
    fi
}

#---------------------------------------------------------------
# 安装模块
#---------------------------------------------------------------

# 安装Docker
install_docker() {
    print_subtitle "安装 Docker 运行时环境"
    
    if cmd_exists docker; then
        print_color $COLOR_GREEN "Docker 已存在，跳过安装"
        return 0
    fi
    
    # 创建Docker配置
    if [[ ! -f $DOCKER_CONFIG_FILE ]]; then
        mkdir -p "$DOCKER_CONFIG_FOLDER"
        cat > "$DOCKER_CONFIG_FILE" <<EOF
{
  "graph": "${installer_path}/${DOCKER_PATH_SUFFIX}",
  "hosts": ["unix:///var/run/docker.sock"],
  "log-driver": "json-file",
  "log-opts": {
      "max-size": "124m",
      "max-file": "10"
  }
}
EOF
    fi
    
    # 根据系统版本安装Docker
    local os_version=""
    if [[ -f /etc/redhat-release ]]; then
        os_version=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_version=$(echo "$VERSION_ID" | cut -d'.' -f1)
    fi
    
    case $os_version in
        7|*kylin*)
            chmod -R +x "${BASE_DIR}/fit2cloud/tools/docker/bin/"
            cp -p "${BASE_DIR}/fit2cloud/tools/docker/bin/"* /usr/bin/
            cp "${BASE_DIR}/fit2cloud/tools/docker/service/docker.service" /etc/systemd/system/
            chmod 754 /etc/systemd/system/docker.service
            ;;
        8)
            local docker_log="/var/log/docker-install.log"
            rpm -ivh "${BASE_DIR}/fit2cloud/tools/docker-rhel8/"*.rpm --force --nodeps >> "$docker_log" 2>&1
            cp "${BASE_DIR}/fit2cloud/tools/docker-rhel8/docker-compose" /usr/local/bin
            chmod +x /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
            sed -i 's@-H fd:// @@g' /usr/lib/systemd/system/docker.service
            ;;
        20|22|24)
            chmod -R +x "${BASE_DIR}/fit2cloud/tools/docker/bin/"
            cp -p "${BASE_DIR}/fit2cloud/tools/docker/bin/"* /usr/bin/
            cp "${BASE_DIR}/fit2cloud/tools/docker/service/docker.service" /etc/systemd/system/
            chmod 754 /etc/systemd/system/docker.service
            ;;
        *)
            print_color $COLOR_RED "不支持的操作系统版本"
            return 1
            ;;
    esac
    
    # 启动Docker服务
    safe_execute "systemctl daemon-reload" "加载systemd配置"
    safe_execute "systemctl start docker" "启动Docker服务"
    safe_execute "systemctl enable docker" "设置Docker开机启动"
    
    # 配置系统参数
    if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
        echo "vm.max_map_count=262144" >> /etc/sysctl.conf
        sysctl -p /etc/sysctl.conf >> "$INSTALL_LOG"
    fi
    
    print_color $COLOR_GREEN "Docker 安装完成"
}

# 加载Docker镜像
load_docker_images() {
    print_subtitle "加载 Docker 镜像"
    
    local images_dir="${BASE_DIR}/docker-images"
    if [[ ! -d $images_dir ]]; then
        print_color $COLOR_RED "镜像目录不存在: $images_dir"
        return 1
    fi
    
    for image_file in "$images_dir"/*.tar "$images_dir"/*.tgz 2>/dev/null; do
        [[ ! -f $image_file ]] && continue
        
        local filename=$(basename "$image_file")
        printf "加载镜像 %-45s ... " "$filename"
        
        if docker load -q -i "$image_file" >> "$INSTALL_LOG" 2>&1; then
            print_color $COLOR_GREEN "[OK]"
        else
            print_color $COLOR_RED "[FAILED]"
        fi
    done
}

# 配置FIT2CLOUD服务
configure_fit2cloud_service() {
    print_subtitle "配置 FIT2CLOUD 服务"
    
    # 复制文件
    cp -rp "${BASE_DIR}/fit2cloud" "$installer_path"
    rm -rf "${installer_path}/fit2cloud/bin/fit2cloud"
    
    # 设置权限
    chmod -R 777 "${installer_path}/fit2cloud/data"
    chmod -R 777 "${installer_path}/fit2cloud/git"
    chmod -R 777 "${installer_path}/fit2cloud/sftp"
    chmod -R 777 "${installer_path}/fit2cloud/conf/rabbitmq"
    chmod -R 777 "${installer_path}/fit2cloud/logs/rabbitmq"
    chmod 644 "${installer_path}/fit2cloud/conf/my.cnf"
    
    # 安装服务脚本
    cp "${SCRIPT_DIR}/fit2cloud.service" /etc/init.d/fit2cloud
    chmod a+x /etc/init.d/fit2cloud
    cp "${SCRIPT_DIR}/f2cctl" /usr/bin/f2cctl
    chmod a+x /usr/bin/f2cctl
    
    # 配置系统服务
    if [[ -f /etc/redhat-release ]] || [[ -f /etc/kylin-release ]]; then
        chkconfig --add fit2cloud 2>/dev/null || systemctl enable fit2cloud
        
        if [[ -f /etc/rc.d/rc.local ]]; then
            if ! grep -q "service fit2cloud start" /etc/rc.d/rc.local; then
                echo "sleep 10" >> /etc/rc.d/rc.local
                echo "service fit2cloud start" >> /etc/rc.d/rc.local
            fi
            chmod +x /etc/rc.d/rc.local
        fi
    else
        systemctl enable fit2cloud 2>/dev/null || true
    fi
    
    print_color $COLOR_GREEN "FIT2CLOUD 服务配置完成"
}

# 安装MinIO
install_minio() {
    local install_dir=$1
    local port=$2
    
    print_subtitle "安装 MinIO 服务"
    
    open_firewall_port "$port"
    
    local minio_script="${installer_path}/fit2cloud/tools/minio/minio-install.sh"
    if [[ -f $minio_script ]]; then
        cd "$(dirname "$minio_script")"
        bash "$(basename "$minio_script")" -d "$install_dir" -p "$port"
    else
        print_color $COLOR_RED "MinIO安装脚本不存在: $minio_script"
        return 1
    fi
}

#---------------------------------------------------------------
# 主流程
#---------------------------------------------------------------

# 显示欢迎信息
show_welcome() {
    cat << EOF

███████╗██╗████████╗██████╗  ██████╗██╗      ██████╗ ██╗   ██╗██████╗ 
██╔════╝██║╚══██╔══╝╚════██╗██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
█████╗  ██║   ██║    █████╔╝██║     ██║     ██║   ██║██║   ██║██║  ██║
██╔══╝  ██║   ██║   ██╔═══╝ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║     ██║   ██║   ███████╗╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
╚═╝     ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝

EOF
    
    local version=$(cat "${BASE_DIR}/fit2cloud/conf/version" 2>/dev/null || echo "未知版本")
    print_color $COLOR_YELLOW "开始安装 $SYSTEM_NAME，版本: $version"
}

# 系统预检测
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

# 获取用户配置
get_user_config() {
    # 安装路径配置
    read -p "CloudExplorer将安装到：${DEFAULT_INSTALL_PATH}/fit2cloud，如需更改请输入自定义路径，否则按回车继续: " custom_path
    installer_path=${custom_path:-$DEFAULT_INSTALL_PATH}
    
    if [[ ! -d $installer_path ]]; then
        print_color $COLOR_RED "输入的目录不存在: $installer_path"
        exit 1
    fi
    
    # 更新安装路径配置
    if [[ $installer_path != "$DEFAULT_INSTALL_PATH" ]]; then
        update_install_path "$installer_path"
    fi
    
    # MinIO安装配置
    read -p "是否安装MinIO服务器? [y/n](默认y): " install_minio
    install_minio=${install_minio:-y}
    
    if [[ $install_minio == "n" ]]; then
        configure_minio
    else
        # MinIO安装路径
        read -p "MinIO将使用默认安装路径${installer_path}/fit2cloud，如需更改请输入自定义路径: " minio_path
        minio_path=${minio_path:-${installer_path}/fit2cloud}
        
        # MinIO端口配置
        while true; do
            read -p "MinIO将使用默认访问端口${DEFAULT_MINIO_PORT}，如需更改请输入自定义端口: " minio_port
            minio_port=${minio_port:-$DEFAULT_MINIO_PORT}
            
            if [[ $minio_port =~ ^[0-9]+$ ]] && [[ $minio_port -ge 1 ]] && [[ $minio_port -le 65535 ]]; then
                if check_minio_port "$minio_port"; then
                    break
                fi
            else
                print_color $COLOR_RED "请输入有效的端口号(1-65535)"
            fi
        done
        
        read -p "确认MinIO安装使用路径: ${minio_path}/MinIO 和端口: ${minio_port}? [y/n](默认y): " confirm
        if [[ ${confirm:-y} == "n" ]]; then
            print_color $COLOR_RED "用户取消安装"
            exit 1
        fi
    fi
}

# 执行安装
perform_install() {
    print_title "开始安装 $SYSTEM_NAME"
    
    # 创建日志文件
    > "$INSTALL_LOG"
    
    # 安装步骤
    install_docker
    load_docker_images
    configure_fit2cloud_service
    
    # 安装MinIO
    if [[ $install_minio == "y" ]]; then
        install_minio "$minio_path" "$minio_port"
    fi
    
    # 配置访问地址
    local system_ips=($(get_system_ip))
    configure_cmp_address "${system_ips[*]}"
    
    print_title "$SYSTEM_NAME 安装完成"
    print_color $COLOR_GREEN "安装成功！请使用以下命令管理服务："
    echo "  启动服务: systemctl start fit2cloud"
    echo "  停止服务: systemctl stop fit2cloud"
    echo "  查看状态: systemctl status fit2cloud"
    echo
    print_color $COLOR_GREEN "Web访问地址: http://$(get_system_ip)"
}

#---------------------------------------------------------------
# 主程序入口
#---------------------------------------------------------------

main() {
    # 静默模式处理
    if [[ $1 == "-s" ]]; then
        nohup bash "${SCRIPT_DIR}/install-silent.sh" >> install.log 2>&1 &
        exit 0
    fi
    
    # 初始化变量
    installer_path=$DEFAULT_INSTALL_PATH
    install_minio="y"
    minio_path=""
    minio_port=$DEFAULT_MINIO_PORT
    
    # 执行主流程
    show_welcome
    pre_install_check
    get_user_config
    perform_install
}

# 执行主程序
main "$@"