#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_influxdb() {
    local url=$(get_env_value CE_INFLUXDB_URL "http://influxdb:8086" "$ENV_FILE")

    if mw_check_external "InfluxDB" "CE_EXTERNAL_INFLUXDB" "$url" ""; then
        if mw_check_url "${url}/ping"; then
            log_ok
            return 0
        else
            log_step_error "外部 InfluxDB 不可达"
            return 1
        fi
    fi
}

install_influxdb() {
    mw_skip_install "InfluxDB" "CE_EXTERNAL_INFLUXDB"
}

configure_influxdb() {
    if mw_skip_configure "InfluxDB" "CE_EXTERNAL_INFLUXDB"; then
        return 0
    fi
    log_info "InfluxDB: 由 Docker Compose 管理，无需额外配置"
}
