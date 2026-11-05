#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

[[ -n "${_F2C_RENDER_SOURCED:-}" ]] && return 0

_F2C_RENDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_F2C_RENDER_DIR/common.sh"

readonly _F2C_RENDER_SOURCED=1

get_render_bin() {
    local base_dir
    base_dir="$(cd "$_F2C_RENDER_DIR/.." && pwd)"
    local platform=$(get_env_value PLATFORM "" "$base_dir/.env")

    if [[ -z "$platform" ]]; then
        local arch=$(uname -m)
        case "$arch" in
            aarch64|arm64) platform="arm64" ;;
            x86_64|amd64)  platform="amd64" ;;
            *)             return 1 ;;
        esac
    fi

    local render_bin="$base_dir/bin/fit2cloud/standalone/ce-render-cfg-${platform}"

    if [[ -x "$render_bin" ]]; then
        echo "$render_bin"
    else
        return 1
    fi
}

# 渲染配置模板
# 用法: do_render <env 文件（逗号分隔可多个，后者覆盖前者）> <模板目录> <输出目录> [加密键列表]
do_render() {
    local env_file="$1"
    local template_dir="$2"
    local output_dir="$3"
    local encrypt_keys="${4:-PASSWORD SECRET KEY}"

    if [[ ! -f "$env_file" && "$env_file" != *,* ]]; then
        log_error ".env 文件不存在: $env_file"
        return 1
    fi

    if [[ ! -d "$template_dir" ]]; then
        log_error "模板目录不存在: $template_dir"
        return 1
    fi

    ensure_dir "$output_dir"

    local render_bin
    render_bin=$(get_render_bin) || {
        log_error "ce-render-cfg 未找到 (PLATFORM=$(get_env_value PLATFORM "" "$(cd "$_F2C_RENDER_DIR/.." && pwd)/.env"), arch=$(uname -m))"
        return 1
    }

    log_info "渲染引擎: $(basename "$render_bin")"

    # 支持逗号分隔的多个 env 文件，后面的文件覆盖前面的同名变量
    local -a env_args=()
    local f
    # 逗号分隔列表按空白展开是有意的（env 文件路径不含空白）
    # shellcheck disable=SC2086
    for f in ${env_file//,/ }; do
        if [[ ! -f "$f" ]]; then
            log_warn "env 文件不存在，跳过: $f"
            continue
        fi
        env_args+=(-e "$f")
    done
    if [[ ${#env_args[@]} -eq 0 ]]; then
        log_error "没有可用的 env 文件"
        return 1
    fi

    local -a encrypt_args=()
    local key
    for key in $encrypt_keys; do
        encrypt_args+=(--encrypt "$key")
    done

    # bash 4.2（CentOS 7）在 set -u 下展开空数组会报未绑定变量，需先判长度
    if [[ ${#encrypt_args[@]} -gt 0 ]]; then
        "$render_bin" -t "$template_dir" -o "$output_dir" "${env_args[@]}" "${encrypt_args[@]}"
    else
        "$render_bin" -t "$template_dir" -o "$output_dir" "${env_args[@]}"
    fi
    log_success "配置渲染完成"
}
