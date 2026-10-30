#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec bash "$FIT2CLOUD_DIR/scripts/install.sh" "$@"
