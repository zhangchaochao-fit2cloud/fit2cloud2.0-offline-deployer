#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/common.sh"

prepare() {
    print_title "步骤 1/5: 准备安装包文件"

    # shellcheck disable=SC2034  # 预留参数：保持调用签名 (output_dir, installer_dir, base_dir)
    local output_dir="$1"
    local installer_dir="$2"
    local base_dir="$3"

    ensure_dir "$installer_dir"

    if [[ -d "$base_dir/extensions" ]]; then
        mv "$base_dir/extensions" "$installer_dir/"
        log_info "扩展文件复制完成"
    fi

    cp -rp "$base_dir/opt"/* "$installer_dir/"

    local installer_env="$installer_dir/fit2cloud/.env"
    cat > "$installer_env" << EOF
# 由打包脚本自动生成，仅包含镜像和版本基本信息
# 安装配置请分别参考 install.env.example（安装期）与 runtime.env.example（运行期）
IMAGE_ADDRESS=${REGISTRY_URL:-registry.fit2cloud.com/north}
VERSION=${FIT2CLOUD_VERSION:-dev-preview}
PLATFORM=${PLATFORM:-amd64}
EOF
    log_info ".env 已生成（仅含 IMAGE_ADDRESS/VERSION/PLATFORM）"

    local aws_price_zip="$installer_dir/fit2cloud/conf/aws_price.json.zip"
    if [[ -f "$aws_price_zip" ]]; then
        unzip -o "$aws_price_zip" -d "$installer_dir/fit2cloud/conf/" >/dev/null 2>&1
        log_info "AWS 询价 JSON 解压完成"
    fi

    rm -rf "$installer_dir/fit2cloud/data/mysql"/* 2>/dev/null || true

    # 打包净化：清除运行时残留与构建机本地的用户配置，防止混入安装包
    # （bin 目录保持 opt/fit2cloud 原有布局，安装脚本按 fit2cloud/bin/fit2cloud/standalone 定位运维入口）
    rm -rf "$installer_dir/fit2cloud/data/minio/.minio.sys" 2>/dev/null || true
    rm -rf "$installer_dir/fit2cloud/logs"/* 2>/dev/null || true
    rm -f "$installer_dir/fit2cloud/install.env" "$installer_dir/fit2cloud/runtime.env" 2>/dev/null || true
    find "$installer_dir" -name ".DS_Store" -delete 2>/dev/null || true

    # Python 实验版本：若构建时启用了 --with-python，将 scripts_py/ 复制进安装包
    if [[ "${WITH_PYTHON:-false}" == "true" ]]; then
        if [[ -d "$base_dir/opt/fit2cloud/scripts_py" ]]; then
            cp -rp "$base_dir/opt/fit2cloud/scripts_py" "$installer_dir/fit2cloud/scripts_py"
            # 写版本标记：安装时 install.py 可读此文件确认 Python 脚本已存在
            cat > "$installer_dir/fit2cloud/scripts_py/.version" << EOF
enabled=true
build_version=${FIT2CLOUD_VERSION}.${BUILD_NUMBER}
build_time=$(date "+%Y-%m-%d %H:%M")
EOF
            log_info "Python 实验版本已包含（scripts_py/）"
        else
            log_warn "scripts_py/ 目录不存在，跳过 Python 版本打包"
        fi
    fi

    log_success "安装包文件准备完成"
}
