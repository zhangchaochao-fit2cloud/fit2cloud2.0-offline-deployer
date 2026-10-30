#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_keycloak() {
    local url=$(get_env_value CE_KEYCLOAK_URL "http://keycloak:8080/auth" "$ENV_FILE")

    if mw_check_external "Keycloak" "CE_EXTERNAL_KEYCLOAK" "$url" ""; then
        if mw_check_url "${url}/"; then
            log_ok
            return 0
        else
            log_step_error "外部 Keycloak 不可达"
            return 1
        fi
    fi
}

install_keycloak() {
    mw_skip_install "Keycloak" "CE_EXTERNAL_KEYCLOAK"
}

configure_keycloak() {
    if mw_skip_configure "Keycloak" "CE_EXTERNAL_KEYCLOAK"; then
        return 0
    fi

    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    mw_set_permissions "Keycloak" "$installer_path/fit2cloud/conf/keycloak/keycloak.properties"
}
