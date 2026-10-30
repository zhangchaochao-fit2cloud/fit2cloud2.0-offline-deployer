#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_mysql() {
    local host=$(get_env_value CE_MYSQL_HOST "mysql" "$ENV_FILE")
    local port=$(get_env_value CE_MYSQL_PORT "3306" "$ENV_FILE")

    if mw_check_external "MySQL" "CE_EXTERNAL_MYSQL" "$host:$port"; then
        if check_mysql_connection "$host" "$port"; then
            log_ok
            return 0
        else
            log_step_error "外部 MySQL 不可达"
            return 1
        fi
    fi
}

install_mysql() {
    mw_skip_install "MySQL" "CE_EXTERNAL_MYSQL"
}

configure_mysql() {
    if mw_skip_configure "MySQL" "CE_EXTERNAL_MYSQL"; then
        return 0
    fi

    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    mw_set_permissions "MySQL" "$installer_path/fit2cloud/conf/mysql/mysql.env"
}

check_mysql_connection() {
    local host="${1:-mysql}"
    local port="${2:-3306}"
    local user="${3:-root}"

    if cmd_exists mysql; then
        mysql -h "$host" -P "$port" -u "$user" -e "SELECT 1" &>/dev/null
    elif cmd_exists nc; then
        nc -z "$host" "$port" 2>/dev/null
    elif cmd_exists telnet; then
        timeout 3 bash -c "echo quit | telnet $host $port" &>/dev/null
    else
        check_port "$port"
    fi
}
