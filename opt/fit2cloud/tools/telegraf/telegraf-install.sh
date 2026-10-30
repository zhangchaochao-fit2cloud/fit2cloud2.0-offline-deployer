#!/bin/bash
# shellcheck disable=SC2034  # 本文件的变量由 source 的中间件脚本读取，shellcheck 静态不可见

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$FIT2CLOUD_DIR/scripts/common.sh"
source "$FIT2CLOUD_DIR/scripts/middleware/telegraf.sh"

INSTALLER_PATH="${CE_INSTALL_PATH:-/opt}"
ENV_FILE="$FIT2CLOUD_DIR/.env"

install_telegraf
configure_telegraf
