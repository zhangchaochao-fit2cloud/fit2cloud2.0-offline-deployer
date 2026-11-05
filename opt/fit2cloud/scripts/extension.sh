#!/bin/bash
# 库文件：扩展模块安装/升级（f2cctl install-module、fit2cloud-install-extension、
# fit2cloud-upgrade-extension 共用，避免三份几乎相同的实现各自漂移）
# 错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

[[ -n "${_F2C_EXTENSION_SOURCED:-}" ]] && return 0

_F2C_EXTENSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_F2C_EXTENSION_DIR/common.sh"
source "$_F2C_EXTENSION_DIR/docker.sh"
source "$_F2C_EXTENSION_DIR/service.sh"

readonly _F2C_EXTENSION_SOURCED=1

# 扩展包内 compose 的镜像地址替换为当前安装环境的仓库地址
_extension_rewrite_registry() {
    local compose_file="$1"
    local image_address="${2:-}"
    local upstream="registry.fit2cloud.com/north"

    [[ -z "$image_address" || "$image_address" == "$upstream" ]] && return 0

    local escaped
    escaped=$(escape_sed_replacement "$image_address")
    replace_in_file "$compose_file" "s|${upstream}|${escaped}|g"
    log_info "镜像仓库地址: $upstream → $image_address"
}

# 输出 compose 中声明的容器名（每行一个）
_extension_container_names() {
    local compose_file="$1"
    sed -n 's/^[[:space:]]*container_name:[[:space:]]*//p' "$compose_file" \
        | tr -d "\"'" | awk 'NF'
}

# 实际执行体：在子 shell 中调用，失败由 apply_extension 统一收口并清理临时目录
_extension_do_apply() {
    local mode="$1"
    local extension_file="$2"
    local work_dir="$3"
    local env_file="$4"
    local tmp_dir="$5"

    local extension_root="$tmp_dir/extension"
    local extension_dir="$work_dir/extensions"
    local compose_file="$extension_root/docker-compose.yml"

    log_info "解压扩展模块..."
    tar zxf "$extension_file" -C "$tmp_dir"

    if [[ ! -f "$compose_file" ]]; then
        log_error "扩展包缺少 docker-compose.yml"
        return 1
    fi

    local image_address
    image_address=$(get_env_value IMAGE_ADDRESS "registry.fit2cloud.com/north" "$env_file")
    _extension_rewrite_registry "$compose_file" "$image_address"

    local service_name="" module_names="" name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        module_names="$module_names $name"
        [[ -z "$service_name" ]] && service_name="$name"
    done < <(_extension_container_names "$compose_file")

    if [[ -z "$service_name" ]]; then
        log_error "扩展包 compose 未定义 container_name，无法确定模块目录"
        return 1
    fi

    local module_dir="$extension_dir/$service_name"
    local installed=false
    [[ -f "$module_dir/docker-compose.yml" ]] && installed=true

    # auto：已安装则升级，否则安装
    if [[ "$mode" == "auto" ]]; then
        if [[ "$installed" == "true" ]]; then mode="upgrade"; else mode="install"; fi
    fi
    if [[ "$mode" == "upgrade" && "$installed" != "true" ]]; then
        log_error "模块未安装，无法升级: $service_name（请使用 install-module 安装）"
        return 1
    fi

    # 先加载镜像再停旧服务，缩短停机窗口
    local image_file
    for image_file in "$extension_root"/*.tar; do
        [[ -f "$image_file" ]] || continue
        log_info_inline "加载镜像 $(basename "$image_file")"
        docker load -qi "$image_file"
        log_ok
    done

    local compose_exe compose_args
    compose_exe=$(get_docker_compose_exe "$env_file") || return 1
    compose_args=$(get_compose_files "$work_dir" "$env_file")

    if [[ "$mode" == "upgrade" ]]; then
        log_info "停止原有服务:$module_names"
        # shellcheck disable=SC2086
        ( cd "$work_dir" && $compose_exe $compose_args -f "$module_dir/docker-compose.yml" rm -sf $module_names ) 2>/dev/null || true
        docker image prune -f >/dev/null 2>&1 || true
        cp -f "$module_dir/docker-compose.yml" "$module_dir/docker-compose.yml.bak"
    else
        ensure_dir "$module_dir"
    fi

    cp -f "$compose_file" "$module_dir/"

    local ext_conf="$extension_root/conf"
    local module_conf="$work_dir/conf/$service_name"
    if [[ -d "$ext_conf" ]]; then
        ensure_dir "$module_conf"
        cp -rf "$ext_conf/." "$module_conf/"
    fi

    local ext_script="$extension_root/scripts/install.sh"
    [[ "$mode" == "upgrade" ]] && ext_script="$extension_root/scripts/upgrade.sh"
    if [[ -f "$ext_script" ]]; then
        log_info "执行模块自带脚本: $(basename "$ext_script")"
        bash "$ext_script" --install_dir "$module_conf" --work_dir "$work_dir"
    fi

    log_info "启动模块: $service_name..."
    # shellcheck disable=SC2086
    ( cd "$work_dir" && $compose_exe $compose_args -f "$module_dir/docker-compose.yml" up -d --no-recreate $module_names )

    local action="安装"
    [[ "$mode" == "upgrade" ]] && action="升级"
    log_success "模块${action}完成: $service_name"
}

# 安装/升级扩展模块
# 用法: apply_extension <install|upgrade|auto> <扩展包> <安装目录> <env 文件>
apply_extension() {
    local mode="$1"
    local extension_file="$2"
    local work_dir="$3"
    local env_file="$4"

    case "$mode" in
        install|upgrade|auto) ;;
        *) log_error "内部错误: 未知扩展模式 $mode"; return 1 ;;
    esac

    if [[ -z "$extension_file" ]]; then
        log_error "未指定扩展模块包"
        return 1
    fi
    if [[ ! -f "$extension_file" ]]; then
        log_error "文件不存在: $extension_file"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/f2c-extensions.XXXXXX") || return 1

    local rc=0
    ( _extension_do_apply "$mode" "$extension_file" "$work_dir" "$env_file" "$tmp_dir" ) || rc=$?
    rm -rf "$tmp_dir"

    return "$rc"
}
