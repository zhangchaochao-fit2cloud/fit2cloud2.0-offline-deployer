#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/common.sh"
source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/docker.sh"

download_tools() {
    print_title "步骤 4/5: 下载工具包"

    local tools_dir="$1"
    local platform="${PLATFORM:-amd64}"

    ensure_dir "$tools_dir"

    log_info "下载 Docker 安装包..."
    # 显式传入打包环境配置的下载地址（packaging.env 的 DOCKER_PACKAGE_URL*），未配置时由 download_docker 按 env 文件/默认值解析
    download_docker "$tools_dir/docker" "${DOCKER_PACKAGE_URL:-}" "${DOCKER_PACKAGE_URL_ARM64:-}" "${DOCKER_PACKAGE_URL_RHEL8:-}"

    if [[ -n "${MINIO_DOCKER_IMAGE:-}" ]]; then
        log_info "拉取 MinIO 镜像: $MINIO_DOCKER_IMAGE"
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            docker pull --platform="linux/${platform}" "$MINIO_DOCKER_IMAGE" 2>/dev/null || true
            ensure_dir "$tools_dir/minio"
            docker save -o "$tools_dir/minio/minio.tar" "$MINIO_DOCKER_IMAGE" 2>/dev/null || true
            log_info "MinIO 镜像已保存"
        fi
    fi

    if [[ -n "${TELEGRAF_PACKAGE_URL:-}" ]]; then
        log_info "下载 Telegraf 安装包..."
        ensure_dir "$tools_dir/telegraf"
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            download_file "$TELEGRAF_PACKAGE_URL" "$tools_dir/telegraf/telegraf.rpm"
        fi
    fi

    log_success "工具包下载完成"
}
