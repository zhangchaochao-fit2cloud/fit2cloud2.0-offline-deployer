#!/bin/bash
# Fit2Cloud 2.0 安装包根入口：转发到安装主脚本
# 用法: bash install.sh [-s 静默安装] [其他参数同 scripts/install.sh]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$DIR/fit2cloud/scripts/install.sh" "$@"
