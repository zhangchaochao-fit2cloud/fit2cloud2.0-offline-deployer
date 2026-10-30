#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

DEFAULT_MINIO_DATA_DIR="$MW_BASE_DIR/../data/minio"

generate_random_key() {
    local length=${1:-20}
    tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$length" || {
        echo "$(date +%s)${RANDOM}${RANDOM}" | md5sum | head -c "$length"
    }
}

check_minio() {
    local endpoint=$(get_env_value CE_MINIO_ENDPOINT "" "$ENV_FILE")

    if mw_check_external "MinIO" "CE_EXTERNAL_MINIO" "$endpoint" ""; then
        if mw_check_url "${endpoint}/minio/health/live"; then
            log_ok
            return 0
        else
            log_step_error "外部 MinIO 不可达"
            return 1
        fi
    fi
}

install_minio() {
    if mw_is_external "CE_EXTERNAL_MINIO"; then
        log_info "MinIO: 使用外部，跳过安装"
        return 0
    fi

    if [[ "${SILENT_MODE:-false}" == "true" ]]; then
        configure_minio_auto
    else
        install_minio_interactive
    fi
}

install_minio_interactive() {
    echo -e "${GREEN}【MinIO】${NC}\n"
    local choice=$(read_with_default "是否安装 MinIO 服务器? [y/n]" "y")
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        configure_external_minio_interactive
    else
        configure_local_minio_interactive
    fi
}

configure_external_minio_interactive() {
    log_info "不安装文件服务器，请配置已有的仓库"

    local repo=$(read_with_default "仓库地址 (例: http://10.1.13.111:9001)" "")
    local minio_ak=$(read_with_default "AccessKey" "")
    local minio_sk=$(read_with_default "SecretKey" "")
    local bucket=$(read_with_default "Bucket" "default")

    set_env_value CE_EXTERNAL_MINIO true "$ENV_FILE"
    set_env_value CE_MINIO_ENDPOINT "$repo" "$ENV_FILE"
    set_env_value CE_MINIO_ACCESS_KEY "$minio_ak" "$ENV_FILE"
    set_env_value CE_MINIO_SECRET_KEY "$minio_sk" "$ENV_FILE"
    set_env_value CE_MINIO_DEFAULT_BUCKET "$bucket" "$ENV_FILE"

    log_info "可在 管理中心 → 系统设置 → 系统参数 中搜索 MinIO 进行管理"
}

configure_local_minio_interactive() {
    local api_port=$(read_with_default "MinIO API 端口" "9000")
    local web_port=$(read_with_default "MinIO 访问端口" "9001")

    while true; do
        if ! check_port "$api_port"; then
            log_warn "端口 $api_port 已占用，请重新输入"
            read -r -p "MinIO API 端口 [$api_port]: " api_port
            continue
        fi
        if ! check_port "$web_port"; then
            log_warn "端口 $web_port 已占用，请重新输入"
            read -r -p "MinIO 访问端口 [$web_port]: " web_port
            continue
        fi
        break
    done

    configure_minio_auto "" "$api_port" "$web_port"
}

configure_minio_auto() {
    local install_path="${1:-$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")}"
    local api_port="${2:-$(get_env_value CE_MINIO_API_PORT "9000" "$ENV_FILE")}"
    local web_port="${3:-$(get_env_value CE_MINIO_WEB_PORT "9001" "$ENV_FILE")}"

    local minio_data_dir="$install_path/fit2cloud/data/minio"
    ensure_dir "$minio_data_dir"

    if [[ -d "$DEFAULT_MINIO_DATA_DIR" ]]; then
        cp -rp "$DEFAULT_MINIO_DATA_DIR/"* "$minio_data_dir/"
    fi

    set_env_value CE_EXTERNAL_MINIO false "$ENV_FILE"
    set_env_value CE_MINIO_API_PORT "$api_port" "$ENV_FILE"
    set_env_value CE_MINIO_WEB_PORT "$web_port" "$ENV_FILE"

    local access_ip=$(get_env_value CE_ACCESS_IP "" "$ENV_FILE")
    if [[ -z "$access_ip" ]]; then
        access_ip=$(get_local_ip)
    fi
    set_env_value CE_MINIO_ENDPOINT "http://$access_ip:$api_port" "$ENV_FILE"

    local minio_access_key=$(get_env_value CE_MINIO_ACCESS_KEY "" "$ENV_FILE")
    local minio_secret_key=$(get_env_value CE_MINIO_SECRET_KEY "" "$ENV_FILE")

    if [[ -z "$minio_access_key" ]]; then
        minio_access_key=$(generate_random_key 20)
        set_env_value CE_MINIO_ACCESS_KEY "$minio_access_key" "$ENV_FILE"
    fi
    if [[ -z "$minio_secret_key" ]]; then
        minio_secret_key=$(generate_random_key 40)
        set_env_value CE_MINIO_SECRET_KEY "$minio_secret_key" "$ENV_FILE"
    fi

    set_env_value CE_MINIO_DEFAULT_BUCKET "default" "$ENV_FILE"
}

configure_minio() {
    if mw_skip_configure "MinIO" "CE_EXTERNAL_MINIO"; then
        return 0
    fi

    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    mw_set_permissions "MinIO" "$installer_path/fit2cloud/conf/minio/minio.env"
}
