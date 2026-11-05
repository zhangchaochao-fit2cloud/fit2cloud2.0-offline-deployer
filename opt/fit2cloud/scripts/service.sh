#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加
# 职责：compose 编排调用 + 服务状态/健康检查/镜像备份/清理（f2cctl、fit2cloud.service、install.sh 共用）

# source 守卫：被多个入口 source，避免重复定义
[[ -n "${_F2C_SERVICE_SOURCED:-}" ]] && return 0

_F2C_SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_F2C_SERVICE_DIR/common.sh"
source "$_F2C_SERVICE_DIR/docker.sh"

readonly _F2C_SERVICE_SOURCED=1

# =============================================================================
# compose 参数拼装
# =============================================================================

# 输出 compose 全局参数串（--env-file / --profile / -f 组合），由调用方按空白展开。
# --profile 必须是 compose 的全局参数（子命令之前）：docker compose ps/logs/stop 不接受
# 子命令形式的 --profile，放后面会直接 unknown flag
get_compose_files() {
    local install_dir="$1"
    local env_file="$2"
    local compose_dir="$install_dir/external-compose"
    local -a compose_args=()

    if [[ -n "$env_file" && -f "$env_file" ]]; then
        compose_args+=("--env-file" "$env_file")
    fi

    local profiles
    profiles=$(get_env_value CE_PROFILES "" "$env_file")
    if [[ -n "$profiles" && "$profiles" != "all" ]]; then
        local profile
        local -a profile_list=()
        IFS=',' read -ra profile_list <<< "$profiles"
        for profile in "${profile_list[@]}"; do
            [[ -n "$profile" ]] && compose_args+=("--profile" "$profile")
        done
    fi

    local ce_mode=$(get_env_value CE_MODE "standalone" "$env_file")
    if [[ "$ce_mode" == "cluster" && -f "$compose_dir/ha-docker-compose.yml" ]]; then
        compose_args+=("-f" "$compose_dir/ha-docker-compose.yml")
    elif [[ -f "$compose_dir/base-docker-compose.yml" ]]; then
        compose_args+=("-f" "$compose_dir/base-docker-compose.yml")
    fi

    local mw mw_upper mw_list="mysql redis influxdb rabbitmq minio keycloak ansible"
    for mw in $mw_list; do
        # ${var^^} 需 bash 4+，用 tr 取大写，兼容开发机 bash 3.2
        mw_upper=$(printf '%s' "$mw" | tr '[:lower:]' '[:upper:]')
        local external=$(get_env_value "CE_EXTERNAL_$mw_upper" "false" "$env_file")
        local compose_file="$compose_dir/middleware/${mw}-docker-compose.yml"
        if [[ "$external" != "true" && -f "$compose_file" ]]; then
            compose_args+=("-f" "$compose_file")
        fi
    done

    if [[ -f "$compose_dir/middleware/websockify-docker-compose.yml" ]]; then
        compose_args+=("-f" "$compose_dir/middleware/websockify-docker-compose.yml")
    fi

    local extension_dir="$install_dir/extensions"
    if [[ -d "$extension_dir" ]]; then
        local ext ext_compose
        for ext in "$extension_dir"/*/; do
            ext_compose="${ext}docker-compose.yml"
            if [[ -f "$ext_compose" ]]; then
                compose_args+=("-f" "$ext_compose")
            fi
        done
    fi

    # bash 4.2 + set -u 下空数组展开会报未绑定变量
    echo "${compose_args[*]:-}"
}

# 输出完整 compose 命令（exe + 全局参数串），供需要直接拼命令的调用方捕获
_get_compose_cmd() {
    local install_dir="$1"
    local env_file="$2"
    local compose_exe compose_args
    compose_exe=$(get_docker_compose_exe "$env_file") || return 1
    compose_args=$(get_compose_files "$install_dir" "$env_file")
    echo "$compose_exe $compose_args"
}

# 在安装目录下执行 compose 子命令；在子 shell 内 cd，不改变调用方工作目录
_compose_run() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    local compose_exe compose_args
    compose_exe=$(get_docker_compose_exe "$env_file") || return 1
    compose_args=$(get_compose_files "$install_dir" "$env_file")

    # compose_args 为参数串，有意按空白展开（compose 文件路径不含空白）
    # shellcheck disable=SC2086
    ( cd "$install_dir" && $compose_exe $compose_args "$@" )
}

# =============================================================================
# 服务生命周期
# =============================================================================

# 启动服务：service_up <安装目录> <env> [服务名...] [额外 compose 参数]
service_up() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    # 参数里可能混有 compose 选项（如 --no-recreate），只对服务名提示
    local arg services=""
    for arg in "$@"; do
        [[ "$arg" == -* ]] && continue
        services="$services $arg"
    done
    if [[ -n "$services" ]]; then
        log_info "启动服务:$services..."
    else
        log_info "启动 Fit2Cloud 服务..."
    fi

    _compose_run "$install_dir" "$env_file" up -d "$@"
    log_success "Fit2Cloud 服务启动完成"
}

# 停止服务。不带服务名 = down（移除容器）；带服务名 = stop 单个服务（保留容器）
service_stop() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    _compose_run "$install_dir" "$env_file" stop "$@"
}

service_down() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    log_info "停止 Fit2Cloud 服务..."
    _compose_run "$install_dir" "$env_file" down "$@"
    log_success "Fit2Cloud 服务停止完成"
}

service_restart() {
    local install_dir="$1"
    local env_file="$2"
    local service_name="${3:-}"

    if [[ -n "$service_name" ]]; then
        log_info "重启服务: $service_name..."
        _compose_run "$install_dir" "$env_file" restart "$service_name"
    else
        log_info "重启所有服务..."
        _compose_run "$install_dir" "$env_file" restart
    fi
    log_success "服务重启完成"
}

service_status() {
    local install_dir="$1"
    local env_file="$2"

    _compose_run "$install_dir" "$env_file" ps
}

service_logs() {
    local install_dir="$1"
    local env_file="$2"
    local service_name="${3:-}"
    local tail_lines="${4:-100}"

    if [[ -n "$service_name" ]]; then
        _compose_run "$install_dir" "$env_file" logs --tail="$tail_lines" "$service_name"
    else
        _compose_run "$install_dir" "$env_file" logs --tail="$tail_lines"
    fi
}

# 启动后监测：轮询 compose ps，退出的容器自动重启，直到全部 running/healthy 或超时
# 用法: service_wait_ready <安装目录> <env 文件> [监测分钟数=30]
service_wait_ready() {
    local install_dir="$1"
    local env_file="$2"
    local minutes="${3:-30}"

    local compose_exe compose_args
    compose_exe=$(get_docker_compose_exe "$env_file") || return 1
    compose_args=$(get_compose_files "$install_dir" "$env_file")

    local i ps_out starting exited unhealthy names name
    for (( i = 0; i < minutes * 2; i++ )); do
        # shellcheck disable=SC2086
        ps_out=$( cd "$install_dir" && $compose_exe $compose_args ps 2>/dev/null || true )

        starting=$(printf '%s\n' "$ps_out" | grep -c 'starting' || true)
        exited=$(printf '%s\n' "$ps_out" | grep -c 'Exit' || true)
        unhealthy=$(printf '%s\n' "$ps_out" | grep -c 'unhealthy' || true)

        if [[ "$exited" -gt 0 ]]; then
            names=$(printf '%s\n' "$ps_out" | awk '/Exit/ {print $1}')
            for name in $names; do
                log_warn "容器退出，尝试重启: $name"
                # shellcheck disable=SC2086
                ( cd "$install_dir" && $compose_exe $compose_args up -d "$name" ) || true
            done
        fi

        if [[ "$starting" -ne 0 || "$exited" -ne 0 || "$unhealthy" -ne 0 ]]; then
            echo "${minutes}分钟内将持续监测服务状态，若有异常将自动重启，Ctrl+C 退出监测"
            printf '%s\n' "$ps_out"
            sleep 30
        else
            printf '%s\n' "$ps_out"
            return 0
        fi
    done
}

# =============================================================================
# 状态与信息
# =============================================================================

service_version() {
    local work_dir="$1"
    local version_file="$work_dir/conf/version"

    if [[ -f "$version_file" ]]; then
        head -1 "$version_file"
    else
        echo "版本信息未知"
    fi
}

service_health() {
    local install_dir="$1"
    local env_file="$2"

    local ps_out
    ps_out=$(_compose_run "$install_dir" "$env_file" ps --format '{{.Name}} {{.Status}}' 2>/dev/null || true)
    if [[ -z "$ps_out" ]]; then
        log_error "没有运行中的服务"
        return 1
    fi

    print_title "服务健康检查"

    local line name status all_healthy=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        name="${line%% *}"
        status="${line#* }"
        if [[ "$status" != Up* ]]; then
            printf '%b\n' "  ${RED}✗${NC} $name: 已停止"
            all_healthy=false
        elif [[ "$status" == *unhealthy* ]]; then
            printf '%b\n' "  ${RED}✗${NC} $name: 运行中 (不健康)"
            all_healthy=false
        elif [[ "$status" == *healthy* ]]; then
            printf '%b\n' "  ${GREEN}✓${NC} $name: 运行中 (健康)"
        else
            printf '%b\n' "  ${YELLOW}○${NC} $name: 运行中"
        fi
    done <<< "$ps_out"

    echo ""
    if [[ "$all_healthy" == "true" ]]; then
        log_success "所有服务健康"
        return 0
    fi
    log_warn "部分服务异常"
    return 1
}

service_disk() {
    local work_dir="$1"

    print_title "磁盘使用情况"

    echo "系统磁盘:"
    df -h / | awk 'NR==2 {printf "  总空间: %s  已用: %s  可用: %s  使用率: %s\n", $2, $3, $4, $5}'

    echo ""
    echo "Docker 磁盘:"
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    if [[ -d "$docker_root" ]]; then
        df -h "$docker_root" 2>/dev/null | awk 'NR==2 {printf "  总空间: %s  已用: %s  可用: %s  使用率: %s\n", $2, $3, $4, $5}'
    fi

    echo ""
    echo "Fit2Cloud 目录:"
    if [[ -d "$work_dir" ]]; then
        du -sh "$work_dir" 2>/dev/null | awk '{printf "  总大小: %s\n", $1}'
        du -sh "$work_dir/data" 2>/dev/null | awk '{printf "  数据目录: %s\n", $1}'
        du -sh "$work_dir/logs" 2>/dev/null | awk '{printf "  日志目录: %s\n", $1}'
        du -sh "$work_dir/docker-images" 2>/dev/null | awk '{printf "  镜像目录: %s\n", $1}'
    fi
}

# =============================================================================
# 镜像备份与清理
# =============================================================================

# 解析 compose 实际使用的镜像列表（去重；filter 非空时按名称过滤）
_compose_image_list() {
    local install_dir="$1"
    local env_file="$2"
    local filter="${3:-}"

    local images
    images=$(_compose_run "$install_dir" "$env_file" config 2>/dev/null \
        | awk '/^[[:space:]]*image:/ {print $2}' | tr -d "\"'" | sort -u)

    if [[ -n "$filter" ]]; then
        images=$(printf '%s\n' "$images" | grep -- "$filter" || true)
    fi

    printf '%s\n' "$images"
}

# 备份镜像到目录（每镜像一个 tar，原子改名避免半截文件；带超时兜底）
# 用法: service_backup_images <安装目录> <env 文件> <输出目录> [镜像名过滤]
service_backup_images() {
    local install_dir="$1"
    local env_file="$2"
    local out_dir="$3"
    local filter="${4:-}"

    ensure_dir "$out_dir"

    local image_list
    image_list=$(_compose_image_list "$install_dir" "$env_file" "$filter")
    if [[ -z "$image_list" ]]; then
        log_error "未能解析镜像列表，请检查 compose 文件与 .env"
        return 1
    fi

    local timeout_secs="${DOCKER_SAVE_TIMEOUT:-3600}"
    local image name out_file failed=0
    log_info "备份 Docker 镜像 → $out_dir"
    while IFS= read -r image; do
        [[ -z "$image" ]] && continue
        name="${image##*/}"          # 去 registry
        name="${name%%:*}"           # 去 tag
        out_file="$out_dir/${name}.tar"
        log_info_inline "$name"
        if timeout "$timeout_secs" docker save -o "$out_file.part" "$image"; then
            mv -f "$out_file.part" "$out_file"
            log_ok
        else
            rm -f "$out_file.part"
            log_step_error "失败"
            failed=1
        fi
    done <<< "$image_list"

    if [[ "$failed" -ne 0 ]]; then
        log_error "部分镜像备份失败: $out_dir"
        return 1
    fi
    log_success "镜像备份完成: $out_dir"
}

service_clean_images() {
    log_info "清理未使用的 Docker 镜像..."
    docker image prune -f
    log_success "镜像已清理"
}

# 清理日志目录下的 history 日志；keep_days<=0 表示全删
service_clean_logs() {
    local log_dir="$1"
    local keep_days="${2:-7}"

    if [[ ! -d "$log_dir" ]]; then
        log_warn "日志目录不存在: $log_dir"
        return 0
    fi

    if [[ "$keep_days" -le 0 ]]; then
        find "$log_dir" -maxdepth 2 -type d -name "history" -exec rm -rf {} + 2>/dev/null || true
        log_success "日志已清理"
    else
        local dir
        while IFS= read -r dir; do
            find "$dir" -type f -name "*.log" -mtime +"$keep_days" -delete 2>/dev/null || true
        done < <(find "$log_dir" -maxdepth 2 -type d -name "history" 2>/dev/null)
        log_success "${keep_days}天前的日志已清理"
    fi
}

# =============================================================================
# 集群状态（cluster 模式）
# =============================================================================

cluster_status() {
    local install_dir="$1"
    local env_file="$2"

    local nodes=$(get_env_value CE_CLUSTER_NODES "" "$env_file")
    if [[ -z "$nodes" ]]; then
        log_error "CE_CLUSTER_NODES 未配置"
        return 1
    fi

    print_title "Fit2Cloud 集群状态"

    local node name ip port_info port svc
    IFS=',' read -ra node_list <<< "$nodes"

    for node in "${node_list[@]}"; do
        name="${node%%:*}"
        ip="${node#*:}"

        echo ""
        echo "[$name] $ip"

        if curl -sf "http://${ip}:6602/actuator/health" >/dev/null 2>&1; then
            echo "  Eureka: ✓ 健康"
        else
            echo "  Eureka: ✗ 不可达"
        fi

        local ports="6608:dashboard 6610:vm-service 6605:operation-analytics 6604:screen-display 6603:billing-center 6001:orchestrator-service 5920:cloud-worker"
        for port_info in $ports; do
            port="${port_info%%:*}"
            svc="${port_info##*:}"
            if curl -sf "http://${ip}:${port}/actuator/health" >/dev/null 2>&1; then
                echo "  $svc: ✓"
            else
                echo "  $svc: ✗"
            fi
        done
    done

    echo ""
}
