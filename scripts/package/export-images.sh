#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/common.sh"
source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/docker.sh"

export_images() {
    print_title "3/5 导出 Docker 镜像"

    local images_dir="$1"
    local env_file="$2"
    local report_file="$3"

    ensure_dir "$images_dir"

    export_docker_images "$images_dir" "$env_file"

    # 单镜像独立 tar：N 个镜像 = N 个 .tar，安装侧逐个 docker load
    local tar_count
    tar_count=$(find "$images_dir" -maxdepth 1 -name '*.tar' -printf '.' 2>/dev/null | wc -c)

    if [[ -n "$report_file" ]]; then
        cat > "$report_file" <<EOF
{
  "total": $tar_count,
  "output_dir": "$images_dir"
}
EOF
    fi

    log_success "导出 $tar_count 个镜像 tar 到 ${images_dir}"
}
