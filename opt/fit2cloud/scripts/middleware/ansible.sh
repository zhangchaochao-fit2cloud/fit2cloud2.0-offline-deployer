#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_ansible() {
    local host=$(get_env_value CE_ANSIBLE_HOST "http://ansible:8000" "$ENV_FILE")

    if mw_check_external "Ansible" "CE_EXTERNAL_ANSIBLE" "$host" ""; then
        if mw_check_url "${host}/api/v1"; then
            log_ok
            return 0
        else
            log_step_error "外部 Ansible 不可达"
            return 1
        fi
    fi
}

install_ansible() {
    mw_skip_install "Ansible" "CE_EXTERNAL_ANSIBLE"
}

configure_ansible() {
    if mw_skip_configure "Ansible" "CE_EXTERNAL_ANSIBLE"; then
        return 0
    fi
    log_info "Ansible: 由 Docker Compose 管理，无需额外配置"
}
