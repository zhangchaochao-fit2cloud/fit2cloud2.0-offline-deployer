#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_redis() {
    local host=$(get_env_value CE_REDIS_HOST "redis" "$ENV_FILE")
    local port=$(get_env_value CE_REDIS_PORT "6379" "$ENV_FILE")

    if mw_check_external "Redis" "CE_EXTERNAL_REDIS" "$host:$port"; then
        if check_redis_connection "$host" "$port"; then
            log_ok
            return 0
        else
            log_step_error "外部 Redis 不可达"
            return 1
        fi
    fi
}

install_redis() {
    mw_skip_install "Redis" "CE_EXTERNAL_REDIS"
}

configure_redis() {
    if mw_skip_configure "Redis" "CE_EXTERNAL_REDIS"; then
        return 0
    fi

    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    mw_set_permissions "Redis" "$installer_path/fit2cloud/conf/redis/redis.conf"
}

check_redis_connection() {
    local host="${1:-redis}"
    local port="${2:-6379}"

    if cmd_exists redis-cli; then
        redis-cli -h "$host" -p "$port" ping 2>/dev/null | grep -q PONG
    else
        check_port "$port"
    fi
}
