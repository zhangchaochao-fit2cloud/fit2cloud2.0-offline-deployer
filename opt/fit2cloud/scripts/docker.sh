#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="$SCRIPT_DIR/../.env"
DOCKER_CONFIG_FOLDER="/etc/docker"
DOCKER_CONFIG_FILE="${DOCKER_CONFIG_FOLDER}/daemon.json"

source "$SCRIPT_DIR/common.sh"

# Docker 离线包下载地址默认值（可被 env 文件中的同名变量覆盖）
DOCKER_PACKAGE_URL_DEFAULT="https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker.zip"
DOCKER_PACKAGE_URL_ARM64_DEFAULT="https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker-arm64.zip"
DOCKER_PACKAGE_URL_RHEL8_DEFAULT="https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker-rhel8.tar.gz"

detect_compose_cmd() {
    if [[ -n "$COMPOSE_CMD" ]]; then
        return 0
    fi

    if cmd_exists docker; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null)
        if [[ -n "$compose_version" ]]; then
            COMPOSE_CMD="docker compose"
            return 0
        fi
    fi

    if cmd_exists docker-compose; then
        COMPOSE_CMD="docker-compose"
        return 0
    fi

    return 1
}

COMPOSE_CMD=""
detect_compose_cmd || true

# =============================================================================
# Docker Compose 命令检测
# =============================================================================

get_docker_compose_exe() {
    local env_file="${1:-$ENV_FILE}"
    detect_compose_cmd
    if [[ -z "$COMPOSE_CMD" ]]; then
        log_error "未检测到 docker compose 或 docker-compose，请先安装"
        return 1
    fi
    echo "$COMPOSE_CMD"
}

get_all_images() {
    local env_file="${1:-$ENV_FILE}"
    local env_dir
    env_dir="$(cd "$(dirname "$env_file")" && pwd)"

    # 直接从 compose YAML 提取 image 行并按 .env 展开变量。
    # 不走 docker compose config：其会校验 env_file: 指向的安装期路径
    # （打包机上不存在）导致整体失败，解析不到任何镜像
    local raw
    raw=$(grep -h "image:" "$env_dir"/docker-compose.yml "$env_dir"/external-compose/*.yml "$env_dir"/external-compose/*/*.yml 2>/dev/null \
        | sed 's/^[[:space:]]*image:[[:space:]]*//' | tr -d '"' | tr -d "'" | sort -u)

    [[ -z "$raw" ]] && return 0

    # 展开 ${VAR} 形式变量（取 .env 值；.env 未定义的变量保持原样）
    local key value
    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}"
        [[ -z "$key" || "$key" == \#* ]] && continue
        value="${value%%#*}"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        # 单引号是有意的：替换目标是字面 ${KEY} 文本，不能让 shell 先展开
        # shellcheck disable=SC2016
        raw=${raw//'${'$key'}'/$value}
    done < "$env_file"

    echo "$raw"
}

# =============================================================================
# Docker 镜像管理
# =============================================================================

verify_image_arch() {
    local image_name="$1"
    local expected_platform="$2"

    local arch
    arch=$(docker inspect --format='{{.Architecture}}' "$image_name" 2>/dev/null)

    if [[ -n "$arch" && "$arch" != "$expected_platform" ]]; then
        log_warn "镜像 $image_name 架构为 $arch, 期望 $expected_platform"
    fi
}

export_docker_images() {
    print_subtitle "导出 Docker 镜像..."

    local images_dir="$1"
    local env_file="$2"
    if [[ -z "$images_dir" ]]; then
        log_warn "没有指定 Docker 导出目录"
        return
    fi

    ensure_dir "$images_dir"

    local compose_images
    compose_images=$(get_all_images "$env_file")
    # Docker 镜像名不含空格，按空白拆分为数组是安全的
    local image_array
    # shellcheck disable=SC2206
    image_array=($compose_images)
    local total=${#image_array[@]}

    if [[ "$total" -eq 0 ]]; then
        log_error "未解析到任何镜像，无法导出"
        return 1
    fi

    # 缓存目录由调用方传入：按单镜像缓存 docker save 结果，命中即硬链接复用，
    # 省掉未变化镜像的重复导出（docker save 单个约 1-10 分钟）
    local cache_dir="${EXPORT_CACHE_DIR:-}"
    if [[ -n "$cache_dir" ]]; then
        ensure_dir "$cache_dir"
        # 清理上次构建被强杀残留的 .part 孤儿文件（正常流程 .part 成功后即改名）
        rm -f "$cache_dir"/*.part "$cache_dir"/*.part.md5 2>/dev/null || true
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run：将导出 $total 个镜像为独立 tar 到 $images_dir（跳过实际导出）"
        return 0
    fi

    local exported=0 cached=0 failed=0

    # 导出单个镜像为独立 tar（命名取镜像名去掉 registry 与 tag，与旧 installer 一致）：
    #   - 安装侧 docker load 逐个加载，单文件损坏只影响该镜像
    #   - 单镜像缓存可精确命中，比整组合并成一个大 tar 更易复用
    export_one() {
        local image_name="$1"
        local base_name="${image_name##*/}"
        local tag="${base_name%%:*}"
        local short_name="${tag%%@*}"
        local out_file="$images_dir/${short_name}.tar"

        # 缓存文件：key 取镜像 ID md5；sidecar md5 由导出时流式生成，
        # manifest 阶段直接复用，免二次全量读取
        local cache_tar="" cache_md5=""
        if [[ -n "$cache_dir" ]]; then
            local image_id
            image_id=$(docker image inspect --format '{{.Id}}' "$image_name" 2>/dev/null)
            if [[ -z "$image_id" ]]; then
                echo "镜像不存在于本地，请先执行 pull 步骤: $image_name"
                return 1
            fi
            local cache_key
            cache_key=$(printf '%s' "${image_id}" | md5sum | awk '{print $1}')
            cache_tar="$cache_dir/${cache_key}-${short_name}.tar"
            cache_md5="$cache_tar.md5"
            # 命中条件要求 tar 与 sidecar md5 同时存在（防止半截缓存被误命中）
            if [[ -s "$cache_tar" && -s "$cache_md5" ]]; then
                ln "$cache_tar" "$out_file" 2>/dev/null || cp -f "$cache_tar" "$out_file"
                cp -f "$cache_md5" "$out_file.md5"
                echo "ok:缓存命中"
                return 0
            fi
        fi

        # docker save 曾出现守护进程挂死（0 CPU、0 字节增长）无限等待的情况，
        # 用 timeout 兜底：默认 2 小时，可通过 DOCKER_SAVE_TIMEOUT 调整
        if [[ -n "$cache_tar" ]]; then
            # 先写 .part 临时文件，成功后原子改名 —— 进程被杀/断电不会留下半截缓存被误命中
            local cache_part="${cache_tar}.part"
            if ! timeout "${DOCKER_SAVE_TIMEOUT:-7200}" docker save "$image_name" \
                | tee "$cache_part" | md5sum | awk '{print $1}' > "${cache_part}.md5"; then
                rm -f "$cache_part" "${cache_part}.md5"
                echo "docker save 失败或超时（可用 DOCKER_SAVE_TIMEOUT 调整超时秒数）: ${image_name}"
                return 1
            fi
            mv -f "$cache_part" "$cache_tar"
            mv -f "${cache_part}.md5" "$cache_md5"
            ln "$cache_tar" "$out_file" 2>/dev/null || cp -f "$cache_tar" "$out_file"
            cp -f "$cache_md5" "$out_file.md5"
        else
            if ! timeout "${DOCKER_SAVE_TIMEOUT:-7200}" docker save -o "$out_file" "$image_name"; then
                rm -f "$out_file"
                echo "docker save 失败或超时（可用 DOCKER_SAVE_TIMEOUT 调整超时秒数）: ${image_name}"
                return 1
            fi
        fi
        echo "ok"
    }

    # 第一阶段：顺序处理缓存命中（硬链接零拷贝），未命中的进入待导出列表
    local to_export=()
    for image_name in "${image_array[@]}"; do
        local result
        result=$(export_one "$image_name") || true
        if [[ "$result" == ok* ]]; then
            if [[ "$result" == "ok:缓存命中" ]]; then
                log_info "缓存命中: ${image_name}"
            fi
            cached=$((cached + 1))
            exported=$((exported + 1))
        else
            to_export+=("$image_name")
        fi
    done

    # 第二阶段：并发导出未命中的镜像（并发 8，与拉镜像一致）
    if [[ ${#to_export[@]} -gt 0 ]]; then
        log_info "需导出 ${#to_export[@]} 个镜像（并发 8）"
        local tmpdir
        tmpdir=$(mktemp -d)
        local pids=() indices=() idx=0
        local image_name
        for image_name in "${to_export[@]}"; do
            (
                if export_one "$image_name" > "$tmpdir/msg_$idx" 2>&1; then
                    echo ok > "$tmpdir/result_$idx"
                else
                    echo fail > "$tmpdir/result_$idx"
                fi
            ) &
            pids+=($!)
            indices+=("$idx")
            idx=$((idx + 1))
            # 并发控制：达到上限则等待所有已提交的子进程
            if [[ ${#pids[@]} -ge ${EXPORT_CONCURRENCY:-8} ]]; then
                for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
                pids=()
            fi
        done
        for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done

        # 汇总结果，逐个列出成功/失败
        for i in "${indices[@]}"; do
            local r
            r=$(cat "$tmpdir/result_$i" 2>/dev/null || echo fail)
            if [[ "$r" == "ok" ]]; then
                log_info "导出完成: ${to_export[$i]}"
                exported=$((exported + 1))
            else
                log_error "导出失败: ${to_export[$i]}"
                log_error "  $(cat "$tmpdir/msg_$i" 2>/dev/null | tail -1)"
                failed=$((failed + 1))
            fi
        done
        rm -rf "$tmpdir"
    fi

    # 缓存清理：每个镜像名只保留最近 IMAGE_CACHE_KEEP 个版本，防止磁盘无限增长；
    # 不符合 <md5>-<name>.tar 命名的历史缓存（如早期单 tar 格式）按 mtime 只保留最近 1 份，其余清除
    if [[ -n "$cache_dir" && -d "$cache_dir" ]]; then
        local keep=${IMAGE_CACHE_KEEP:-2} stale legacy
        stale=$(ls -t "$cache_dir"/*.tar 2>/dev/null | awk -F/ -v k="$keep" \
            '{ n=$NF; sub(/^[0-9a-f]+-/, "", n); sub(/\.tar$/, "", n); if (seen[n]++ >= k) print }')
        legacy=$(ls -t "$cache_dir"/*.tar 2>/dev/null | grep -vE '/[0-9a-f]{32}-.+\.tar$' | tail -n +2)
        if [[ -n "$stale" || -n "$legacy" ]]; then
            # shellcheck disable=SC2086
            echo "$stale $legacy" | tr ' ' '\n' | sed '/^$/d' | xargs -r rm -f
            # shellcheck disable=SC2086
            echo "$stale $legacy" | tr ' ' '\n' | sed '/^$/d; s/$/.md5/' | xargs -r rm -f
            log_info "镜像导出缓存清理完成（每镜像保留最近 ${keep} 份，历史格式仅保留最近 1 份）"
        fi
    fi

    # 记录本次导出的镜像清单（安装侧对账用）
    printf '%s\n' "${image_array[@]}" > "$images_dir/images.list"

    if [[ "$failed" -gt 0 ]]; then
        log_error "镜像导出失败 $failed 个，成功 $exported/$total"
        return 1
    fi
    if [[ "$cached" -gt 0 ]]; then
        log_success "镜像导出完成: $exported 个镜像文件（缓存命中 $cached）"
    else
        log_success "镜像导出完成: $exported 个镜像文件"
    fi
}

# =============================================================================
# Docker 下载 (打包阶段使用)
# =============================================================================

download_local_docker() {
    local platform=$(get_env_value PLATFORM "amd64" "$ENV_FILE")
    local docker_tools_dir="$1"
    local docker_package="$2"

    local docker_zip=""
    if [[ "$platform" == "arm64" ]]; then
        docker_zip="${FROM_DOCKER_LOCAL_DIR}/docker-arm64.zip"
    else
        docker_zip="${FROM_DOCKER_LOCAL_DIR}/docker.zip"
    fi

    if [[ ! -f "$docker_zip" ]]; then
        log_error "本地 Docker 包不存在: $docker_zip"
        return 1
    fi

    cp -f "$docker_zip" "$docker_tools_dir/$docker_package"

    local redhat_docker_tar="${FROM_DOCKER_LOCAL_DIR}/docker-rhel8.tar.gz"
    if [[ -f "$redhat_docker_tar" ]]; then
        cp -f "$redhat_docker_tar" "$docker_tools_dir/docker-rhel8.tar.gz"
    fi
}

download_remote_docker() {
    local platform=$(get_env_value PLATFORM "amd64" "$ENV_FILE")
    local docker_tools_dir="$1"
    local docker_package="$2"
    local url_amd64="$3"
    local url_arm64="$4"
    local url_rhel8="$5"

    local target_url="$url_amd64"
    if [[ "$platform" == "arm64" ]]; then
        target_url="$url_arm64"
    fi

    cd "$docker_tools_dir" || return 1
    download_file "$target_url" "./$docker_package"
    download_file "$url_rhel8" "./docker-rhel8.tar.gz"
    cd - > /dev/null || return 1
}

download_docker() {
    local platform=$(get_env_value PLATFORM "amd64" "$ENV_FILE")
    local docker_package="docker_${platform}.zip"

    local docker_tools_dir="$1"
    if [[ -z "$docker_tools_dir" ]]; then
        log_error "没有指定 Docker 下载目录"
        return 1
    fi

    # 下载地址解析优先级：调用方显式传入（打包侧 packaging.env 覆盖）> env 文件 > 内置默认值
    local url_amd64="${2:-$(get_env_value DOCKER_PACKAGE_URL "$DOCKER_PACKAGE_URL_DEFAULT" "$ENV_FILE")}"
    local url_arm64="${3:-$(get_env_value DOCKER_PACKAGE_URL_ARM64 "$DOCKER_PACKAGE_URL_ARM64_DEFAULT" "$ENV_FILE")}"
    local url_rhel8="${4:-$(get_env_value DOCKER_PACKAGE_URL_RHEL8 "$DOCKER_PACKAGE_URL_RHEL8_DEFAULT" "$ENV_FILE")}"

    ensure_dir "$docker_tools_dir"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info_inline "下载 Docker 安装包"
        log_step_success "跳过"
        return
    fi

    log_info "下载 Docker 安装包..."
    if [[ -n "${FROM_DOCKER_LOCAL_DIR:-}" && -d "${FROM_DOCKER_LOCAL_DIR}" ]]; then
        download_local_docker "$docker_tools_dir" "$docker_package"
    else
        download_remote_docker "$docker_tools_dir" "$docker_package" "$url_amd64" "$url_arm64" "$url_rhel8"
    fi

    cd "$docker_tools_dir" || return 1
    unzip -q "$docker_package"
    rm -f "$docker_package"
    rm -rf __MACOSX
    cd - > /dev/null || return 1

    log_ok
}

# =============================================================================
# Docker 检查与安装
# =============================================================================

check_docker() {
    log_info_inline "Docker 检测..."
    if ! cmd_exists docker; then
        log_step_error "未安装"
        return 1
    fi
    log_ok

    docker_start

    log_info_inline "Docker 版本..."
    local version
    version=$(docker info --format '{{.ServerVersion}}' 2>/dev/null)
    local major_version
    major_version=$(echo "$version" | awk -F. '{print $1}')
    local minor_version
    minor_version=$(echo "$version" | awk -F. '{print $2}')
    if [[ -z "$major_version" ]]; then
        log_step_error "无法获取版本"
        return 1
    fi

    local min_major=18
    local min_minor=9
    if [[ "$major_version" -lt "$min_major" ]] || [[ "$major_version" -eq "$min_major" && "$minor_version" -lt "$min_minor" ]]; then
        log_step_error "需要 >= ${min_major}.${min_minor}"
        return 1
    fi
    log_ok "版本 $version"

    local docker_dir
    docker_dir=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
    log_info "Docker 存储目录: ${docker_dir:-未知}，请确保空间充足"
    return 0
}

check_docker_compose() {
    log_info_inline "Docker Compose 检测..."

    if cmd_exists docker; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null)
        if [[ -n "$compose_version" ]]; then
            log_ok "docker compose (V2) 版本 $compose_version"
            return 0
        fi
    fi

    if cmd_exists docker-compose; then
        local compose_version
        compose_version=$(docker-compose version --short 2>/dev/null)
        if [[ -n "$compose_version" ]]; then
            local major_version
            major_version=$(echo "$compose_version" | awk -F. '{print $1}')
            if [[ "$major_version" -ge 1 ]]; then
                log_ok "docker-compose 版本 $compose_version"
                return 0
            fi
        fi
    fi

    log_step_error "未安装"
    return 1
}

# =============================================================================
# Docker 安装与配置
# =============================================================================

install_docker() {
    if cmd_exists docker; then
        log_info "Docker 已安装，跳过"
        return 0
    fi

    print_subtitle "安装 Docker..."

    local installer_path
    installer_path=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
    local docker_path="$installer_path/fit2cloud/docker"
    local docker_log_max_size
    docker_log_max_size=$(get_env_value CE_DOCKER_LOG_MAX_SIZE "10m" "$ENV_FILE")
    local docker_log_max_file
    docker_log_max_file=$(get_env_value CE_DOCKER_LOG_MAX_FILE "3" "$ENV_FILE")

    ensure_dir "$docker_path"

    if [[ ! -f "$DOCKER_CONFIG_FILE" ]]; then
        ensure_dir "$DOCKER_CONFIG_FOLDER"
        cat > "$DOCKER_CONFIG_FILE" <<EOF
{
  "data-root": "${docker_path}",
  "hosts": ["unix:///var/run/docker.sock"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${docker_log_max_size}",
    "max-file": "${docker_log_max_file}"
  },
  "storage-driver": "overlay2"
}
EOF
        log_info "daemon.json 已生成"
    fi

    log_info_inline "安装 Docker 二进制..."
    local os_version=""
    local os_name=""
    if [[ -f /etc/redhat-release ]]; then
        os_version=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
        os_name="redhat"
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_version=$(echo "$VERSION_ID" | cut -d'.' -f1)
        # shellcheck disable=SC2153  # NAME 来自 /etc/os-release，非拼写错误
        os_name="${NAME,,}"
    fi

    # 麒麟系统识别
    local is_kylin=false
    if grep -qi "kylin" /etc/os-release 2>/dev/null; then
        is_kylin=true
    fi

    local tools_docker_dir="$SCRIPT_DIR/../tools/docker"
    # 麒麟系统 V10/V11 走 RHEL8 分支；V7 走 RHEL7 分支
    case "$os_version" in
        7)
            if [[ "$is_kylin" == "true" ]]; then
                rpm -ivh "$tools_docker_dir/docker-rhel8/"*.rpm --force --nodeps
            else
                chmod -R +x "$tools_docker_dir/bin/"
                cp -p "$tools_docker_dir/bin/"* /usr/bin/
                cp "$tools_docker_dir/service/docker.service" /etc/systemd/system/
                chmod 754 /etc/systemd/system/docker.service
            fi
            ;;
        8|10|11)
            rpm -ivh "$tools_docker_dir/docker-rhel8/"*.rpm --force --nodeps
            cp "$tools_docker_dir/docker-rhel8/docker-compose" /usr/local/bin/
            chmod +x /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
            ;;
        20|22|24)
            chmod -R +x "$tools_docker_dir/bin/"
            cp -p "$tools_docker_dir/bin/"* /usr/bin/
            cp "$tools_docker_dir/service/docker.service" /etc/systemd/system/
            chmod 754 /etc/systemd/system/docker.service
            ;;
        *)
            log_step_error "不支持的系统版本: $os_version (os_name=$os_name)"
            return 1
            ;;
    esac
    log_ok

    safe_execute "加载 systemd 配置" systemctl daemon-reload
    safe_execute "启动 Docker" systemctl start docker
    safe_execute "设置 Docker 开机启动" systemctl enable docker

    # 验证 Docker 是否成功启动
    if ! docker info >/dev/null 2>&1; then
        log_step_error "Docker 启动失败，请检查日志"
        return 1
    fi

    if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
        log_info_inline "配置系统参数..."
        echo "vm.max_map_count=262144" >> /etc/sysctl.conf
        sysctl -p /etc/sysctl.conf >> "${INSTALL_LOG:-/dev/null}" 2>&1
        log_ok
    fi
}

docker_start() {
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        systemctl start docker
        systemctl enable docker
    fi
}
