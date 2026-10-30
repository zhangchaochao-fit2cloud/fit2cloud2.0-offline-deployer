#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/docker.sh"

get_compose_files() {
    local install_dir="$1"
    local env_file="$2"
    local compose_dir="$install_dir/external-compose"
    local -a compose_args=()

    if [[ -n "$env_file" && -f "$env_file" ]]; then
        compose_args+=("--env-file" "$env_file")
    fi

    local ce_mode=$(get_env_value CE_MODE "standalone" "$env_file")
    if [[ "$ce_mode" == "cluster" && -f "$compose_dir/ha-docker-compose.yml" ]]; then
        compose_args+=("-f" "$compose_dir/ha-docker-compose.yml")
    elif [[ -f "$compose_dir/base-docker-compose.yml" ]]; then
        compose_args+=("-f" "$compose_dir/base-docker-compose.yml")
    fi

    local mw_list="mysql redis influxdb rabbitmq minio keycloak ansible"
    for mw in $mw_list; do
        local external=$(get_env_value "CE_EXTERNAL_${mw^^}" "false" "$env_file")
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
        for ext in "$extension_dir"/*/; do
            local ext_compose="$ext/docker-compose.yml"
            if [[ -f "$ext_compose" ]]; then
                compose_args+=("-f" "$ext_compose")
            fi
        done
    fi

    echo "${compose_args[*]}"
}

_get_profile_args() {
    local env_file="$1"
    local profiles=$(get_env_value CE_PROFILES "" "$env_file")

    if [[ -z "$profiles" ]]; then
        return
    fi

    if [[ "$profiles" == "all" ]]; then
        return
    fi

    IFS=',' read -ra profile_list <<< "$profiles"
    for profile in "${profile_list[@]}"; do
        echo "--profile $profile"
    done
}

_run_compose() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    cd "$install_dir" || return 1

    local compose_cmd
    compose_cmd=$(_get_compose_cmd "$install_dir" "$env_file")
    $compose_cmd "$@"
}

_get_compose_cmd() {
    local install_dir="$1"
    local env_file="$2"
    local compose_args
    compose_args=$(get_compose_files "$install_dir" "$env_file")
    local compose_exe
    compose_exe=$(get_docker_compose_exe "$env_file")
    echo "$compose_exe $compose_args"
}

service_up() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    local profile_args="$(_get_profile_args "$env_file")"

    log_info "启动 Fit2Cloud 服务..."
    _run_compose "$install_dir" "$env_file" up -d $profile_args "$@"
    log_success "Fit2Cloud 服务启动完成"
}

service_down() {
    local install_dir="$1"
    local env_file="$2"
    shift 2

    local profile_args="$(_get_profile_args "$env_file")"

    log_info "停止 Fit2Cloud 服务..."
    _run_compose "$install_dir" "$env_file" down $profile_args "$@"
    log_success "Fit2Cloud 服务停止完成"
}

service_restart() {
    local install_dir="$1"
    local env_file="$2"
    local service_name="$3"

    local profile_args="$(_get_profile_args "$env_file")"

    if [[ -n "$service_name" ]]; then
        log_info "重启服务: $service_name..."
        _run_compose "$install_dir" "$env_file" restart $profile_args "$service_name"
    else
        log_info "重启所有服务..."
        _run_compose "$install_dir" "$env_file" restart $profile_args
    fi
    log_success "服务重启完成"
}

service_status() {
    local install_dir="$1"
    local env_file="$2"

    local profile_args="$(_get_profile_args "$env_file")"

    _run_compose "$install_dir" "$env_file" ps $profile_args
}

service_logs() {
    local install_dir="$1"
    local env_file="$2"
    local service_name="$3"
    local tail_lines="${4:-100}"

    local profile_args="$(_get_profile_args "$env_file")"

    if [[ -n "$service_name" ]]; then
        _run_compose "$install_dir" "$env_file" logs --tail="$tail_lines" $profile_args "$service_name"
    else
        _run_compose "$install_dir" "$env_file" logs --tail="$tail_lines" $profile_args
    fi
}

cluster_status() {
    local install_dir="$1"
    local env_file="$2"

    local nodes=$(get_env_value CE_CLUSTER_NODES "" "$env_file")
    if [[ -z "$nodes" ]]; then
        log_error "CE_CLUSTER_NODES 未配置"
        return 1
    fi

    print_title "Fit2Cloud 集群状态"

    IFS=',' read -ra node_list <<< "$nodes"

    for node in "${node_list[@]}"; do
        local name="${node%%:*}"
        local ip="${node#*:}"

        echo ""
        echo "[$name] $ip"

        local eureka_url="http://${ip}:6602/actuator/health"
        if curl -sf "$eureka_url" >/dev/null 2>&1; then
            echo "  Eureka: ✓ 健康"
        else
            echo "  Eureka: ✗ 不可达"
        fi

        local ports="6608:dashboard 6610:vm-service 6605:operation-analytics 6604:screen-display 6603:billing-center 6001:orchestrator-service 5920:cloud-worker"
        for port_info in $ports; do
            local port="${port_info%%:*}"
            local svc="${port_info##*:}"
            if curl -sf "http://${ip}:${port}/actuator/health" >/dev/null 2>&1; then
                echo "  $svc: ✓"
            else
                echo "  $svc: ✗"
            fi
        done
    done

    echo ""
}
