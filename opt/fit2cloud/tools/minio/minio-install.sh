#!/bin/bash
# shellcheck disable=SC2034  # 本文件的变量由 source 的中间件脚本读取，shellcheck 静态不可见

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$FIT2CLOUD_DIR/scripts/common.sh"
source "$FIT2CLOUD_DIR/scripts/middleware/minio.sh"

ENV_FILE="$FIT2CLOUD_DIR/.env"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) CE_INSTALL_PATH="$2"; shift 2 ;;
        -p) CE_MINIO_WEB_PORT="$2"; shift 2 ;;
        *)  shift ;;
    esac
done

install_minio
configure_minio
