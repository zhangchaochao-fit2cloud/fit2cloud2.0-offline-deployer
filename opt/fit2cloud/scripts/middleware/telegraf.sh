#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_telegraf() {
    local install_telegraf=$(get_env_value CE_INSTALL_TELEGRAF "true" "$ENV_FILE")
    if [[ "$install_telegraf" != "true" ]]; then
        return 0
    fi

    if cmd_exists telegraf; then
        log_info "Telegraf: 已安装"
        log_ok
        return 0
    else
        log_info "Telegraf: 未安装"
        return 1
    fi
}

install_telegraf() {
    local install_telegraf=$(get_env_value CE_INSTALL_TELEGRAF "true" "$ENV_FILE")
    if [[ "$install_telegraf" != "true" ]]; then
        log_info "Telegraf: 跳过安装"
        return 0
    fi

    if cmd_exists telegraf; then
        log_info "Telegraf: 已安装，跳过"
        return 0
    fi

    print_subtitle "安装 Telegraf..."

    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    local telegraf_dir="$installer_path/fit2cloud/tools/telegraf"

    if cmd_exists rpm; then
        local rpm_file=$(ls "$telegraf_dir/"*.rpm 2>/dev/null | head -1)
        if [[ -n "$rpm_file" ]]; then
            rpm -ivh "$rpm_file"
        else
            log_warn "未找到 Telegraf RPM 包"
            return 0
        fi
    elif cmd_exists dpkg; then
        local deb_file=$(ls "$telegraf_dir/"*.deb 2>/dev/null | head -1)
        if [[ -n "$deb_file" ]]; then
            dpkg -i "$deb_file"
        else
            log_warn "未找到 Telegraf DEB 包"
            return 0
        fi
    else
        log_warn "不支持的包管理系统，跳过 Telegraf 安装"
        return 0
    fi

    log_success "Telegraf 安装完成"
}

configure_telegraf() {
    local install_telegraf=$(get_env_value CE_INSTALL_TELEGRAF "true" "$ENV_FILE")
    if [[ "$install_telegraf" != "true" ]]; then
        return 0
    fi

    local interval=$(get_env_value CE_TELEGRAF_INTERVAL "10s" "$ENV_FILE")
    local installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    local telegraf_conf="$installer_path/fit2cloud/conf/telegraf/telegraf.conf"

    if [[ -f "$telegraf_conf" ]]; then
        if grep -q "^interval" "$telegraf_conf" 2>/dev/null; then
            sed -i "s/^interval.*/interval = \"$interval\"/" "$telegraf_conf"
        else
            sed -i "s/# interval = \"10s\"/interval = \"$interval\"/" "$telegraf_conf"
        fi
        log_info "Telegraf 采集间隔: $interval"
    fi

    if [[ -f "$telegraf_conf" ]] && cmd_exists systemctl; then
        cp "$telegraf_conf" /etc/telegraf/telegraf.conf
        systemctl enable telegraf 2>/dev/null || true
    fi
}
