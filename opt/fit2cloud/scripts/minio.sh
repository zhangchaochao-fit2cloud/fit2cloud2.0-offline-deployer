#!/bin/bash

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认 data 目录
DEFAULT_MINIO_DATA_DIR="$SCRIPT_DIR/../data/minio"

source "$SCRIPT_DIR/common.sh"

install_minio() {
    log_title_info "MinIO"
    choice=$(read_with_default "1. 是否安装 MinIO 服务器? [y/n] " "y")
    echo -e "${choice}\n"
    if [[ "$choice" =~ ^[Nn]$ ]]; then
      configure_external_minio
    else
      configure_local_minio
    fi
}

configure_external_minio() {
    echo "不安装文件服务器，请配置已有的仓库"

    read -p "仓库地址（例如：http://10.1.13.111:9001）:" repo
    read -p "AccessKey:" minio_ak
    read -p "SecretKey:" minio_sk
    read -p "Bucket:" bucket

    set_env_value CE_EXTERNAL_MINIO true
    set_env_value CE_MINIO_ENDPOINT $repo
    set_env_value CE_MINIO_ACCESS_KEY $minio_ak
    set_env_value CE_MINIO_SECRET_KEY $minio_sk
    set_env_value CE_MINIO_DEFAULT_BUCKET $bucket
    echo "可在 管理中心 → 系统设置 → 系统参数 中搜索 MinIO 进行管理"
}

configure_local_minio() {

    local installer_path=$(get_env_value CE_MINIO_INSTALL_PATH "/opt/fit2cloud/data/minio")

    while true; do
        minio_folder=$(read_with_default "2. MinIO 安装路径" "${installer_path}")
        echo -e "${minio_folder}\n"

        api_port=$(read_with_default "3. MinIO API端口" "9000")
        echo -e "${api_port}\n"

        web_port=$(read_with_default "4. MinIO 访问端口" "9001")
        echo -e "${web_port}\n"

        echo -e "5. MinIO 端口占用："
        web_port="${web_port:-9001}"
        if ! check_port "$api_port"; then
          continue
        fi
        if ! check_port "$web_port"; then
          continue
        fi

        # 最终确认
        echo
        sure=$(read_with_default "6. 确认 MinIO 安装路径: $minio_folder，端口: $api_port, $web_port ? [y/n]: " "y")
        echo -e "${sure}\n"
        if [[ "$sure" =~ ^[Nn]$ ]]; then
          echo -e "已取消安装\n"
          continue
        fi
        break
    done
    mkdir -p $minio_folder

    # 自定义路径需要移动文件到该目录
    if [ ! "$installer_path" == "$minio_folder" ]; then
        cp -rp "$DEFAULT_MINIO_DATA_DIR/*" $minio_folder
    fi

    set_env_value CE_EXTERNAL_MINIO false
    set_env_value CE_MINIO_INSTALL_PATH $minio_folder
    set_env_value CE_MINIO_API_PORT $api_port
    set_env_value CE_MINIO_WEB_PORT $web_port

    local access_ip=$(get_env_value CE_ACCESS_IP)
    set_env_value CE_MINIO_ENDPOINT "http://$access_ip:$api_port"
    set_env_value CE_MINIO_ACCESS_KEY "gzD4Mt5YSA1KQr1XnxSZ"
    set_env_value CE_MINIO_SECRET_KEY "JQ1z9O5rcGZx1xsUjpadaRy0jQKdB56lGs3vDbEX"
    set_env_value CE_MINIO_DEFAULT_BUCKET "default"

}