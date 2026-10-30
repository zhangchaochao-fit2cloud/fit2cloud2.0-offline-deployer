#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$FIT2CLOUD_DIR/scripts/common.sh"
source "$FIT2CLOUD_DIR/scripts/docker.sh"
source "$FIT2CLOUD_DIR/scripts/service.sh"

ENV_FILE="$FIT2CLOUD_DIR/.env"
WORK_DIR=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
WORK_DIR="$WORK_DIR/fit2cloud"

extension_file="${1:-}"
if [[ -z "$extension_file" ]]; then
    echo "用法: fit2cloud-upgrade-extension <FILE>"
    exit 1
fi

if [[ ! -f "$extension_file" ]]; then
    echo "文件不存在: $extension_file"
    exit 1
fi

EXTENSION_DIR="$WORK_DIR/extensions"
tmp_dir="/tmp/f2c-extensions/$(date +%s)"
extension_tmp_dir="$tmp_dir/extension"
ensure_dir "$tmp_dir"

log_info "解压扩展模块..."
tar zxf "$extension_file" -C "$tmp_dir"

compose_file="$extension_tmp_dir/docker-compose.yml"
if [[ ! -f "$compose_file" ]]; then
    log_error "模块缺少 docker-compose.yml"
    rm -rf "$tmp_dir"
    exit 1
fi

image_address=$(get_env_value IMAGE_ADDRESS "registry.fit2cloud.com/north" "$ENV_FILE")
sed -i "s#registry.fit2cloud.com/north#${image_address}#g" "$compose_file"

service_name=""
module_names=""
# shellcheck disable=SC2013  # 容器名列表有意按空白展开
for module_name in $(grep "container_name" "$compose_file" | awk -F "container_name: " '{print $NF}'); do
    module_names="$module_names $module_name"
    if [[ -z "$service_name" ]]; then
        service_name="$module_name"
    fi
done

module_dir="$EXTENSION_DIR/$service_name"
if [[ ! -d "$module_dir" ]]; then
    log_error "未找到扩展模块目录: $module_dir"
    rm -rf "$tmp_dir"
    exit 1
fi

for image_file in "$extension_tmp_dir"/*.tar; do
    [[ ! -f "$image_file" ]] && continue
    log_info_inline "加载镜像 $(basename "$image_file")"
    docker load -qi "$image_file"
    log_ok
done

log_info "停止原有服务: $module_names..."
compose_args=$(get_compose_files "$WORK_DIR" "$ENV_FILE")
if [[ -f "$module_dir/docker-compose.yml" ]]; then
    compose_args="$compose_args -f $module_dir/docker-compose.yml"
fi
compose_exe=$(get_docker_compose_exe "$ENV_FILE")
# shellcheck disable=SC2086  # compose_args/module_names 有意按空白展开
$compose_exe $compose_args rm -sf $module_names 2>/dev/null || true

docker image prune -f &>/dev/null || true

log_info "升级扩展模块: $service_name"
cp -f "$module_dir/docker-compose.yml" "$module_dir/docker-compose.yml.bak"
cp -f "$compose_file" "$module_dir/"

ext_conf="$extension_tmp_dir/conf"
module_conf="$WORK_DIR/conf/$service_name"
if [[ -d "$ext_conf" ]]; then
    ensure_dir "$module_conf"
    cp -rf "$ext_conf/"* "$module_conf/"
fi

ext_upgrade_script="$extension_tmp_dir/scripts/upgrade.sh"
if [[ -f "$ext_upgrade_script" ]]; then
    bash "$ext_upgrade_script" --install_dir "$module_conf" --work_dir "$WORK_DIR"
fi

log_info "启动扩展模块: $service_name..."
compose_args=$(get_compose_files "$WORK_DIR" "$ENV_FILE")
if [[ -f "$module_dir/docker-compose.yml" ]]; then
    compose_args="$compose_args -f $module_dir/docker-compose.yml"
fi
compose_exe=$(get_docker_compose_exe "$ENV_FILE")
$compose_exe $compose_args up --no-recreate -d $module_names

rm -rf "$tmp_dir"
log_success "扩展模块升级完成: $service_name"
