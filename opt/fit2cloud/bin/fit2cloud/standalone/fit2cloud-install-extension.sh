#!/bin/bash
# 安装扩展模块（与 f2cctl install-module 同一实现，保留独立命令供产品/文档调用）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$FIT2CLOUD_DIR/scripts/common.sh"
source "$FIT2CLOUD_DIR/scripts/extension.sh"

WORK_DIR="$(get_env_value CE_INSTALL_PATH "/opt" "$FIT2CLOUD_DIR/.env")/fit2cloud"

[[ -n "${1:-}" ]] || die "用法: fit2cloud-install-extension <FILE>"

apply_extension install "$1" "$WORK_DIR" "$FIT2CLOUD_DIR/.env"
