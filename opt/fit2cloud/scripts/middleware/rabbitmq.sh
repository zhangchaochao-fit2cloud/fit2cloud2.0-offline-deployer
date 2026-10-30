#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_rabbitmq() {
    local host=$(get_env_value CE_RABBITMQ_HOST "rabbitmq" "$ENV_FILE")
    local port=$(get_env_value CE_RABBITMQ_PORT "5672" "$ENV_FILE")

    if mw_check_external "RabbitMQ" "CE_EXTERNAL_RABBITMQ" "$host:$port"; then
        if check_rabbitmq_connection "$host" "$port"; then
            log_ok
            return 0
        else
            log_step_error "外部 RabbitMQ 不可达"
            return 1
        fi
    fi
}

install_rabbitmq() {
    mw_skip_install "RabbitMQ" "CE_EXTERNAL_RABBITMQ"
}

configure_rabbitmq() {
    if mw_skip_configure "RabbitMQ" "CE_EXTERNAL_RABBITMQ"; then
        return 0
    fi

    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    mw_set_permissions "RabbitMQ" "$installer_path/fit2cloud/conf/rabbitmq"
}

check_rabbitmq_connection() {
    local host="${1:-rabbitmq}"
    local port="${2:-5672}"

    if cmd_exists nc; then
        nc -z -w3 "$host" "$port" 2>/dev/null
    elif cmd_exists telnet; then
        timeout 3 bash -c "echo quit | telnet $host $port" &>/dev/null
    else
        check_port "$port"
    fi
}
