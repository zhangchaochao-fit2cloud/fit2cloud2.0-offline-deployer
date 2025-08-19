#!/bin/bash

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/common.sh"

install_minio() {
    read -p "是否安装 MinIO 服务器? [y/n](默认y): " choice
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
    set_env_value CE_EXTERNAL_MINIO false
    local installer_path=$(get_env_value CE_INSTALL_PATH)

    # 安装端口
    while true; do
        read -p "MinIO 将使用默认安装路径$installer_path/fit2cloud，如需更改请输入自定义安装路径:" folder
        if [ ! -n "$folder" ] ;then
          echo "使用默认安装路径$installer_path/fit2cloud"
          folder="$installer_path/fit2cloud"
        else
          echo "使用自定义安装路径$folder"
        fi
        read -p "MinIO 将使用默认访问端口 9001，如需更改请输入自定义端口: " port
        port="${port:-9001}"

        if [[ ! "$port" =~ ^[0-9]+$ ]]; then
          echo "自定义端口必须为纯数字，请重新输入。"
          continue
        fi

        echo "检测端口 $port 是否被占用..."
        if check_port "$port"; then
          echo "使用端口: $port"
          break
        else
          echo "端口 $port 已被占用，请重新输入。"
        fi
    done

    # 最终确认
    read -p "确认 MinIO 安装路径: $folder/MinIO，端口: $port? [y/n](默认y): " sure
    if [[ "$sure" =~ ^[Nn]$ ]]; then
      echo "已取消安装 MinIO。"
      exit 0
    fi
}