#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$BASE_DIR/opt/fit2cloud/scripts"
PACKAGE_DIR="$BASE_DIR/scripts/package"
RENDER_CFG_DIR="$BASE_DIR/render-cfg"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/docker.sh"

FIT2CLOUD_VERSION="2.0"
BUILD_NUMBER="1"
VERSION=""
REGISTRY_URL="registry.fit2cloud.com/north"
PLATFORM="amd64"
OUTPUT_DIR="$BASE_DIR/dist"
DRY_RUN=false
CLEAN_TEMP=false
SKIP_RENDER_CFG=false
WITH_PYTHON=false
PLUGIN_PACKAGES=""
DEPLOYMENT_PACKAGES=""
EXTENSION_PACKAGES=""
ENV_FILE=""
# CLI 显式传入的参数标记（--env-file 只填充未显式指定的项）
OPT_VERSION="" OPT_BUILD_NUMBER="" OPT_REGISTRY="" OPT_OUTPUT_DIR=""
OPT_PLATFORM="" OPT_PLUGIN_PACKAGES="" OPT_DEPLOYMENT_PACKAGES="" OPT_EXTENSION_PACKAGES=""
OPT_WITH_PYTHON=""

show_help() {
    cat << EOF
Fit2Cloud 2.0 打包脚本

用法: $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -v, --version VERSION   版本号 [默认: 2.0]
    -b, --build-number NUM  构建号 [默认: 1]
    -V, --image-version TAG 镜像 tag [默认: <版本号>.<构建号>，勿用 master 等开发标签]
    -r, --registry URL      镜像仓库地址 [默认: registry.fit2cloud.com/north]
    -o, --output-dir DIR    输出目录 [默认: ./dist]
    --platform PLATFORM     目标平台 [默认: amd64]
    --dry-run               试运行模式
    --clean                 清理临时文件
    -p, --plugin-packages   插件包目录（多个用逗号分隔）
    -d, --deployment-packages 中间件包 URL（多个用逗号分隔）
    -e, --extension-packages 扩展包 URL（多个用逗号分隔）
    --env-file FILE         打包环境文件（如 packaging.env，仅填充未在命令行指定的项）
    --skip-render-cfg       跳过 ce-render-cfg 编译
    --with-python           包含 Python 版本脚本（实验性）
    --with-python           在安装包中包含 Python 版本（实验性）

示例:
    $0 -v 2.0.1 -b 100
    $0 -r my-registry.com -v 2.0.1 --platform arm64
    $0 --env-file packaging.env -v 2.0.1 -b 100
    $0 --dry-run -v 2.0.1

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)       show_help; exit 0 ;;
            -v|--version)    FIT2CLOUD_VERSION="$2"; OPT_VERSION=1; shift 2 ;;
            -b|--build-number) BUILD_NUMBER="$2"; OPT_BUILD_NUMBER=1; shift 2 ;;
            -V|--image-version) VERSION="$2"; shift 2 ;;
            -r|--registry)   REGISTRY_URL="$2"; OPT_REGISTRY=1; shift 2 ;;
            -o|--output-dir) OUTPUT_DIR="$2"; OPT_OUTPUT_DIR=1; shift 2 ;;
            --platform)      PLATFORM="$2"; OPT_PLATFORM=1; shift 2 ;;
            --dry-run)       DRY_RUN=true; shift ;;
            --clean)         CLEAN_TEMP=true; shift ;;
            -p|--plugin-packages) PLUGIN_PACKAGES="$2"; OPT_PLUGIN_PACKAGES=1; shift 2 ;;
            -d|--deployment-packages) DEPLOYMENT_PACKAGES="$2"; OPT_DEPLOYMENT_PACKAGES=1; shift 2 ;;
            -e|--extension-packages) EXTENSION_PACKAGES="$2"; OPT_EXTENSION_PACKAGES=1; shift 2 ;;
            --env-file)      ENV_FILE="$2"; shift 2 ;;
            --skip-render-cfg) SKIP_RENDER_CFG=true; shift ;;
            --with-python)   WITH_PYTHON=true; OPT_WITH_PYTHON=1; shift ;;
            *)               log_error "未知参数: $1"; show_help; exit 1 ;;
        esac
    done
}

load_env_file() {
    [[ -z "$ENV_FILE" ]] && return 0

    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "环境文件不存在: $ENV_FILE"
        exit 1
    fi

    log_info "加载打包环境文件: $ENV_FILE"

    local key value
    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}"
        [[ -z "$key" || "$key" == \#* ]] && continue
        # 去掉行内注释和首尾引号
        value="${value%%\#*}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        [[ -z "$value" ]] && continue
        case "$key" in
            FIT2CLOUD_VERSION)       [[ -z "$OPT_VERSION" ]] && FIT2CLOUD_VERSION="$value" ;;
            BUILD_NUMBER)            [[ -z "$OPT_BUILD_NUMBER" ]] && BUILD_NUMBER="$value" ;;
            VERSION)                 VERSION="$value" ;;
            REGISTRY_URL)            [[ -z "$OPT_REGISTRY" ]] && REGISTRY_URL="$value" ;;
            PLATFORM)                [[ -z "$OPT_PLATFORM" ]] && PLATFORM="$value" ;;
            OUTPUT_DIR)              [[ -z "$OPT_OUTPUT_DIR" ]] && OUTPUT_DIR="$value" ;;
            PLUGIN_PACKAGES)         [[ -z "$OPT_PLUGIN_PACKAGES" ]] && PLUGIN_PACKAGES="$value" ;;
            DEPLOYMENT_PACKAGES)     [[ -z "$OPT_DEPLOYMENT_PACKAGES" ]] && DEPLOYMENT_PACKAGES="$value" ;;
            EXTENSION_PACKAGES)      [[ -z "$OPT_EXTENSION_PACKAGES" ]] && EXTENSION_PACKAGES="$value" ;;
            WITH_PYTHON)             [[ -z "$OPT_WITH_PYTHON" ]] && WITH_PYTHON="$value" ;;
            DOCKER_PACKAGE_URL|DOCKER_PACKAGE_URL_ARM64|DOCKER_PACKAGE_URL_RHEL8|TELEGRAF_PACKAGE_URL|MINIO_DOCKER_IMAGE)
                export "$key=$value"
                ;;
            *) : ;;
        esac
    done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE")
}

check_prerequisites() {
    log_info_inline "检查前置条件"

    local required_commands=("docker" "tar" "wget")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_step_error "命令未找到: $cmd"
            exit 1
        fi
    done

    if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
        log_step_error "需要 docker compose V2 或 docker-compose V1"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_step_error "Docker 未运行或无法连接"
        exit 1
    fi

    log_ok
}

build_render_cfg() {
    local installer_dir="$1"

    if ! command -v go &>/dev/null; then
        log_warn "Go 未安装，跳过 ce-render-cfg 编译"
        return
    fi

    print_subtitle "编译 ce-render-cfg..."

    cd "$RENDER_CFG_DIR"
    make cross VERSION="$FIT2CLOUD_VERSION"

    local standalone_dir="$installer_dir/fit2cloud/bin/fit2cloud/standalone"
    ensure_dir "$standalone_dir"

    cp -f "$RENDER_CFG_DIR/bin/ce-render-cfg-amd64" "$standalone_dir/" 2>/dev/null || true
    cp -f "$RENDER_CFG_DIR/bin/ce-render-cfg-arm64" "$standalone_dir/" 2>/dev/null || true

    cd "$BASE_DIR"
    log_success "ce-render-cfg 编译完成"
}

show_package_info() {
    local package_file="$1"

    print_title "Fit2Cloud ${FIT2CLOUD_VERSION} 打包完成！"

    cat << EOF

=============================================================================
打包信息
=============================================================================
版本:      $FIT2CLOUD_VERSION
构建号:    $BUILD_NUMBER
平台:      $PLATFORM
镜像仓库:  $REGISTRY_URL
输出目录:  $OUTPUT_DIR
安装包:    $package_file

=============================================================================

EOF
}

main() {
    parse_args "$@"
    load_env_file

    # 镜像 tag 默认跟随版本号.构建号，避免忘传参数时误用 master 等开发标签
    VERSION="${VERSION:-${FIT2CLOUD_VERSION}.${BUILD_NUMBER}}"

    print_title "开始打包 Fit2Cloud 2.0..."

    check_prerequisites

    INSTALLER_DIR="$OUTPUT_DIR/installer"
    DOCKER_IMAGES_DIR="$INSTALLER_DIR/docker-images"
    CLOUD_PLUGINS_DIR="$OUTPUT_DIR/cloud_plugins"
    TOOLS_DIR="$INSTALLER_DIR/fit2cloud/tools"
    MIDDLEWARE_DIR="$INSTALLER_DIR/fit2cloud/middleware_init"
    EXTENSIONS_DIR="$INSTALLER_DIR/extensions"
    INSTALLER_ENV="$INSTALLER_DIR/fit2cloud/.env"

    # 每次构建清理输出目录，保证包内容只来自本次源码（可复现构建）
    rm -rf "$INSTALLER_DIR" "$CLOUD_PLUGINS_DIR"

    export REGISTRY_URL FIT2CLOUD_VERSION PLATFORM DRY_RUN WITH_PYTHON

    source "$PACKAGE_DIR/prepare.sh"
    prepare "$OUTPUT_DIR" "$INSTALLER_DIR" "$BASE_DIR"

    set_env_value IMAGE_ADDRESS "$REGISTRY_URL" "$INSTALLER_ENV"
    set_env_value PLATFORM "$PLATFORM" "$INSTALLER_ENV"

    if [[ "$SKIP_RENDER_CFG" != "true" ]]; then
        build_render_cfg "$INSTALLER_DIR"
    else
        log_info "跳过 ce-render-cfg 编译 (--skip-render-cfg)"
    fi

    source "$PACKAGE_DIR/pull-images.sh"
    pull_images "$INSTALLER_ENV" "$OUTPUT_DIR/pull-report.json"

    source "$PACKAGE_DIR/export-images.sh"
    export_images "$DOCKER_IMAGES_DIR" "$INSTALLER_ENV" "$OUTPUT_DIR/export-report.json"

    source "$PACKAGE_DIR/download-tools.sh"
    download_tools "$TOOLS_DIR"

    source "$PACKAGE_DIR/create-package.sh"

    copy_plugins "$PLUGIN_PACKAGES" "$CLOUD_PLUGINS_DIR"
    copy_middleware "$DEPLOYMENT_PACKAGES" "$MIDDLEWARE_DIR"
    copy_extensions "$EXTENSION_PACKAGES" "$EXTENSIONS_DIR"

    local build_time=$(date "+%Y%m%d%H%M")
    local build_id="${FIT2CLOUD_VERSION}.${BUILD_NUMBER} Build ${build_time}"

    log_info "镜像 tag: ${VERSION}"
    log_info "构建标识: ${build_id}"

    create_package "$OUTPUT_DIR" "$INSTALLER_DIR" "$build_id" "$PLATFORM" "$OUTPUT_DIR/package-report.json"

    if [[ "$CLEAN_TEMP" == "true" ]]; then
        rm -rf "$INSTALLER_DIR" "$CLOUD_PLUGINS_DIR"
    fi

    local package_filename="cloudexplorer-${FIT2CLOUD_VERSION}.${BUILD_NUMBER}-${VERSION}-$(date '+%Y.%m.%d').tar.gz"
    show_package_info "$package_filename"
}

main "$@"
