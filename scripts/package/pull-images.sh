#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/common.sh"
source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/docker.sh"

# 拉取单个镜像，成功返回 0，失败返回 1
pull_one() {
    local image_name="$1"
    local platform="$2"
    local attempt=1
    while [[ $attempt -le 3 ]]; do
        if docker pull --platform="linux/${platform}" "${image_name}" >/dev/null 2>&1; then
            return 0
        fi
        if [[ $attempt -lt 3 ]]; then
            log_info "拉取失败，重试 ($attempt/3): $(basename "${image_name}")"
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

pull_images() {
    print_title "步骤 2/5: 拉取 Docker 镜像"

    local env_file="$1"
    local report_file="$2"

    local compose_images
    compose_images=$(get_all_images "$env_file")
    local platform
    platform=$(get_env_value PLATFORM "amd64" "$env_file")

    if [[ -z "$compose_images" ]]; then
        log_error "未从 docker compose 配置中解析到任何镜像，请检查 $env_file"
        return 1
    fi

    # shellcheck disable=SC2206  # 镜像名列表按空白拆分为数组
    local image_array=($compose_images)
    local total=${#image_array[@]}
    local pulled=0
    local failed=0
    local failed_images=()

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "试运行：共 ${total} 个镜像，跳过拉取"
        for image_name in "${image_array[@]}"; do
            log_info "  $(basename "$image_name")"
            pulled=$((pulled + 1))
        done
    else
        log_info "拉取 ${total} 个镜像（平台 linux/${platform}，并发 8）"

        local tmpdir
        tmpdir=$(mktemp -d)
        local pids=()
        local indices=()
        local idx=0

        for image_name in "${image_array[@]}"; do
            (
                if pull_one "$image_name" "$platform"; then
                    verify_image_arch "$image_name" "$platform"
                    echo "ok"
                else
                    echo "fail"
                fi
            ) > "$tmpdir/result_$idx" 2>/dev/null &
            pids+=($!)
            indices+=("${idx}")
            idx=$((idx + 1))

            # 并发控制：达到上限则等待所有已提交的子进程
            if [[ ${#pids[@]} -ge 8 ]]; then
                for pid in "${pids[@]}"; do
                    wait "$pid" 2>/dev/null || true
                done
                pids=()
            fi
        done

        # 等待剩余子进程
        for pid in "${pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done

        # 统计结果，失败镜像逐个列出便于排查
        for idx_val in "${indices[@]}"; do
            local result
            result=$(cat "$tmpdir/result_$idx_val" 2>/dev/null || echo "fail")
            if [[ "$result" == "ok" ]]; then
                pulled=$((pulled + 1))
            else
                failed=$((failed + 1))
                failed_images+=("${image_array[$idx_val]}")
            fi
        done
        rm -rf "$tmpdir"
    fi

    if [[ -n "$report_file" ]]; then
        cat > "$report_file" <<EOF
{
  "total": $total,
  "pulled": $pulled,
  "failed": $failed,
  "platform": "$platform"
}
EOF
    fi

    log_info "镜像拉取完成: 成功 ${pulled}/${total}, 失败 ${failed}"
    if [[ $failed -gt 0 ]]; then
        log_error "有 ${failed} 个镜像拉取失败："
        local image
        for image in "${failed_images[@]}"; do
            log_error "  ${image}"
        done
        return 1
    fi
}
