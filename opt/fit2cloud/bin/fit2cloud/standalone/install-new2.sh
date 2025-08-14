#!/bin/bash

# Fit2Cloud 安装脚本优化版

# 日志文件路径
INSTALL_LOG="/tmp/fit2cloud-install.log"

# 默认安装路径
INSTALLER_PATH="/opt"
DOCKER_PATH="$INSTALLER_PATH/fit2cloud/docker"
DOCKER_CONFIG_DIR="/etc/docker"
DOCKER_CONFIG_FILE="$DOCKER_CONFIG_DIR/daemon.json"

# 颜色定义
RED=31
GREEN=32
YELLOW=33
BLUE=34

# 状态变量
validation_passed=1
validation_warning=1
install_minio=true
minio_port_valid=false

# 获取主机 IP 地址
ips=$(ip route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')

# 参数 -s 静默安装支持
if [[ "$1" == "-s" ]]; then
    nohup bash install-silent.sh >> install.log 2>&1 &
    exit 0
fi

# 打印标题
print_title() {
    echo -e "\n\n**********\t $1 \t**********\n"
}

# 打印子标题
print_subtitle() {
    echo -e "------\t \033[${BLUE}m $1 \033[0m \t------\n"
}

# 彩色打印信息
color_msg() {
    echo -e "\033[$1m $2 \033[0m"
}

# 检查端口占用，参数: 端口号
check_port() {
    local port=$1
    local record=0

    if command -v lsof >/dev/null 2>&1; then
        record=$(lsof -iTCP:"$port" -sTCP:LISTEN | wc -l)
    elif command -v netstat >/dev/null 2>&1; then
        record=$(netstat -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    elif command -v ss >/dev/null 2>&1; then
        record=$(ss -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    else
        color_msg $RED "[WARNING] 未检测到 lsof、netstat 或 ss 命令，端口检测跳过"
        return 0
    fi

    echo -ne "$port 端口 \t\t........................ "
    if [[ $record -eq 0 ]]; then
        color_msg $GREEN "[OK]"
        return 0
    else
        validation_passed=0
        color_msg $RED "[被占用]"
        return 1
    fi
}

# 检查MinIO端口，类似check_port但会设置minio_port_valid变量
check_minio_port() {
    local port=$1
    local record=0

    if command -v lsof >/dev/null 2>&1; then
        record=$(lsof -iTCP:"$port" -sTCP:LISTEN | wc -l)
    elif command -v netstat >/dev/null 2>&1; then
        record=$(netstat -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    elif command -v ss >/dev/null 2>&1; then
        record=$(ss -tnl 2>/dev/null | awk '{print $4}' | grep -E "[:.]$port$" | wc -l)
    else
        color_msg $RED "[WARNING] 未检测到 lsof、netstat 或 ss 命令，MinIO端口检测跳过"
        minio_port_valid=true
        return 0
    fi

    echo -ne "$port 端口 \t\t........................ "
    if [[ $record -eq 0 ]]; then
        color_msg $GREEN "[OK]"
        minio_port_valid=true
    else
        color_msg $RED "[被占用]"
        minio_port_valid=false
    fi
}

# 打开防火墙端口，参数：端口号
open_port() {
    local port=$1
    if [[ -z "$port" ]]; then
        return
    fi

    if systemctl is-active firewalld >/dev/null 2>&1; then
        echo -ne "打开防火墙端口 $port \t\t........................ "
        if ! firewall-cmd --list-ports | grep -qw "${port}/tcp"; then
            firewall-cmd --zone=public --add-port=${port}/tcp --permanent >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            systemctl restart docker >/dev/null 2>&1
        fi
        color_msg $GREEN "[OK]"
    fi
}

# 获取 Docker 存储目录
get_docker_dir() {
    docker info --format '{{.DockerRootDir}}' 2>/dev/null
}

# 交互修改安装路径
read_install_path() {
    read -p "CloudExplorer 将安装到：$INSTALLER_PATH/fit2cloud，如需更改请输入自定义路径，否则按回车继续: " ce_path
    if [[ -n "$ce_path" ]]; then
        if [[ ! -d "$ce_path" ]]; then
            color_msg $RED "输入的目录不存在，退出安装~"
            exit 1
        fi
        INSTALLER_PATH="$ce_path"
        DOCKER_PATH="$INSTALLER_PATH/fit2cloud/docker"
        # 替换相关脚本路径
        sed -i "s#f2c_install_dir=\"/opt\"#f2c_install_dir=\"$INSTALLER_PATH\"#g" ../fit2cloud/tools/minio/minio-install.sh
        sed -i "s#dockerPath=\"/opt/fit2cloud/docker\"#dockerPath=\"$DOCKER_PATH\"#g" ../fit2cloud/tools/docker/docker-install.sh
        sed -i "s#work_dir=\"/opt/fit2cloud\"#work_dir=\"$INSTALLER_PATH/fit2cloud\"#g" f2cctl
        sed -i "s#f2c_install_dir=\"/opt\"#f2c_install_dir=\"$INSTALLER_PATH\"#g" fit2cloud.service
        sed -i "s#fit2cloud_dir=\"/opt/fit2cloud\"#fit2cloud_dir=\"$INSTALLER_PATH/fit2cloud\"#g" fit2cloud-install-extension.sh fit2cloud-upgrade-extension.sh
        sed -i "s#installerPath=/opt#installerPath=\"$INSTALLER_PATH\"#g" upgrade.sh ../fit2cloud/.env ../fit2cloud/tools/telegraf/telegraf-install.sh
    else
        echo "使用默认安装路径 $INSTALLER_PATH/fit2cloud"
    fi
}

# 询问是否安装 MinIO 及配置
configure_minio() {
    read -p "是否安装 MinIO 服务器? [y/n] (默认y): " word
    if echo "$word" | grep -iq "^n"; then
        install_minio=false
        echo "不安装文件服务器, 请配置已有仓库(需允许重复部署:allowredeploy)"
        local config_file="$INSTALLER_PATH/fit2cloud/conf/fit2cloud.properties"
        read -p "仓库地址（eg: http://10.1.13.111:9001）:" repo
        {
            echo -e "\n# MinIO 配置"
            echo "minio.endpoint=$repo"
            read -p "accessKey:" minio_ak
            echo "minio.accessKey=$minio_ak"
            read -p "secretKey:" minio_sk
            echo "minio.secretKey=$minio_sk"
            read -p "bucket:" bucket
            echo "minio.bucket.default=$bucket"
        } >> "$config_file"
        echo "配置已写入 $config_file，可在管理中心/系统设置/系统参数中搜索 MinIO 进行管理."
    else
        while :; do
            read -p "MinIO 将使用默认安装路径 $INSTALLER_PATH/fit2cloud，如需更改请输入自定义安装路径: " folder
            folder=${folder:-"$INSTALLER_PATH/fit2cloud"}
            echo "使用安装路径: $folder"

            while :; do
                read -p "MinIO 默认访问端口为 9001，如需更改请输入自定义端口: " port
                port=${port:-9001}
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    echo "检测端口 $port 是否被占用..."
                    check_minio_port "$port"
                    if $minio_port_valid; then
                        echo "使用端口: $port"
                        break
                    else
                        color_msg $RED "端口 $port 被占用，请选择其他端口。"
                    fi
                else
                    color_msg $RED "端口必须为数字，请重新输入。"
                fi
            done

            read -p "确认 MinIO 安装路径: $folder/MinIO 和端口: $port ? [y/n] (默认y): " sure
            sure=${sure:-y}
            if [[ ! "$sure" =~ ^[Nn]$ ]]; then
                break
            fi
        done
    fi
}

# 主流程

# 1. 读安装路径
read_install_path

# 2. 询问是否安装 MinIO
configure_minio

# 3. 打印欢迎信息
cat << "EOF"

███████╗██╗████████╗██████╗  ██████╗██╗      ██████╗ ██╗   ██╗██████╗
██╔════╝██║╚══██╔══╝╚════██╗██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
█████╗  ██║   ██║    █████╔╝██║     ██║     ██║   ██║██║   ██║██║  ██║
██╔══╝  ██║   ██║   ██╔═══╝ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║     ██║   ██║   ███████╗╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
╚═╝     ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝

EOF

# 4. 清空安装日志
> "$INSTALL_LOG"

SYSTEM_NAME="FIT2CLOUD 云管平台 3.0"
VERSION_INFO=$(cat ../fit2cloud/conf/version)

color_msg $YELLOW "\n开始安装 $SYSTEM_NAME，版本 - $VERSION_INFO"

print_title "${SYSTEM_NAME} 安装环境检测"

# root 用户检测
echo -ne "root 用户检测 \t\t........................ "
if [[ "$(id -u)" == 0 ]]; then
    color_msg $GREEN "[OK]"
else
    color_msg $RED "[ERROR] 请使用 root 用户执行安装脚本"
    validation_passed=0
fi

# 操作系统检测
echo -ne "操作系统检测 \t\t........................ "
if [[ -f /etc/redhat-release ]]; then
    os_version=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    major_version=${os_version%%.*}
    if [[ "$major_version" =~ ^(7|8)$ ]]; then
        color_msg $GREEN "[OK]"
    else
        color_msg $RED "[ERROR] 仅支持 CentOS 7.x/8.x, RHEL 7.x/8.x"
        validation_passed=0
    fi
elif [[ -f /etc/kylin-release ]]; then
    color_msg $GREEN "[OK]"
elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        major_version=${VERSION_ID%%.*}
        if [[ "$major_version" =~ ^(20|22|24)$ ]]; then
            color_msg $GREEN "[OK]"
        else
            color_msg $RED "[ERROR] 仅支持 Ubuntu 20/22/24"
            validation_passed=0
        fi
    elif [[ "$ID" == "openEuler" ]]; then
        major_version=${VERSION_ID%%.*}
        if [[ "$major_version" =~ ^(22|23)$ ]]; then
            color_msg $GREEN "[OK]"
        else
            color_msg $RED "[ERROR] 仅支持 EulerOS 22/23"
            validation_passed=0
        fi
    else
        color_msg $RED "[ERROR] 不支持的操作系统"
        validation_passed=0
    fi
else
    color_msg $RED "[ERROR] 无法识别操作系统"
    validation_passed=0
fi

# 架构检测
echo -ne "服务器架构检测 \t\t........................ "
arch=$(uname -m)
if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
    color_msg $GREEN "[OK]"
else
    color_msg $RED "[ERROR] 架构必须是 x86_64 或 aarch64"
    validation_passed=0
fi

# CPU 检测
echo -ne "CPU检测 \t\t........................ "
cpu_count=$(grep -c ^processor /proc/cpuinfo)
if (( cpu_count < 4 )); then
    color_msg $YELLOW "[WARNING] CPU 小于 4 核，建议至少 4 核"
    validation_warning=0
else
    color_msg $GREEN "[OK]"
fi

# 内存检测
echo -ne "内存检测 \t\t........................ "
mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if (( mem_total_kb < 16000000 )); then
    color_msg $YELLOW "[WARNING] 内存小于 16G，建议至少 16G"
    validation_warning=0
else
    color_msg $GREEN "[OK]"
fi

# 磁盘空间检测
echo -ne "磁盘剩余空间检测 \t........................ "
# 获取安装路径所在磁盘剩余空间(kb)
disk_avail_kb=$(df -Pk "$INSTALLER_PATH" | awk 'NR==2 {print $4}')
if (( disk_avail_kb < 200000000 )); then
    color_msg $YELLOW "[WARNING] 剩余空间小于 200G，建议至少 200G"
    validation_warning=0
else
    color_msg $GREEN "[OK]"
fi

# Docker 检测
echo -ne "Docker 检测 \t\t........................ "
if ! command -v docker >/dev/null 2>&1; then
    color_msg $RED "[ERROR] 未安装 Docker"
    validation_passed=0
else
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null | cut -d. -f1)
    if [[ -z "$docker_version" ]]; then
        color_msg $RED "[ERROR] 无法获取 Docker 版本"
        validation_passed=0
    elif (( docker_version < 18 )); then
        color_msg $RED "[ERROR] Docker 版本需 >=18"
        validation_passed=0
    else
        docker_dir=$(get_docker_dir)
        color_msg $GREEN "[OK] 存储目录：$docker_dir"
        echo -ne "docker-compose 检测 \t........................ "
        if ! command -v docker-compose >/dev/null 2>&1; then
            color_msg $RED "[ERROR] 未安装 docker-compose"
            validation_passed=0
        else
            color_msg $GREEN "[OK]"
        fi
    fi
fi

# 检测需要的端口是否被占用
fit2cloud_ports=$(awk '/ports:/,/\[/{if($0 ~ /- /) print $0}' ../fit2cloud/docker-compose.yml | awk -F':' '{print $1}' | tr -d '- ')
for port in $fit2cloud_ports; do
    check_port "$port"
done

# 环境检测结果判断
if (( validation_passed == 0 )); then
    color_msg $RED "\n${SYSTEM_NAME} 安装环境检测未通过，请检查上述错误信息\n"
    exit 1
fi

if (( validation_warning == 0 )); then
    echo
    read -p "${SYSTEM_NAME} 安装环境检测存在警告，建议配置 4C 16G 200G。是否忽略并继续? [y/n](默认y): " skip_warning
    skip_warning=${skip_warning:-y}
    if [[ "$skip_warning" =~ ^[Nn]$ ]]; then
        color_msg $RED "\n${SYSTEM_NAME} 安装环境检测未通过，请检查上述警告\n"
        exit 1
    fi
fi

print_title "开始进行${SYSTEM_NAME} 安装"

# 后续安装逻辑（省略，你可以继续基于原脚本内容写）

