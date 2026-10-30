#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# 安装期变量（模式/路径/集群/组件开关）；运行期变量（中间件/密码/性能）见 RUNTIME_ENV
INSTALL_ENV="$FIT2CLOUD_DIR/install.env"
RUNTIME_ENV="$FIT2CLOUD_DIR/runtime.env"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/docker.sh"
source "$SCRIPT_DIR/os.sh"
source "$SCRIPT_DIR/render.sh"
source "$SCRIPT_DIR/service.sh"

MW_DIR="$SCRIPT_DIR/middleware"
source "$MW_DIR/mysql.sh"
source "$MW_DIR/redis.sh"
source "$MW_DIR/influxdb.sh"
source "$MW_DIR/rabbitmq.sh"
source "$MW_DIR/minio.sh"
source "$MW_DIR/keycloak.sh"
source "$MW_DIR/ansible.sh"
source "$MW_DIR/nginx.sh"
source "$MW_DIR/telegraf.sh"

COMPLETED_STEPS=""
PROGRESS_FILE=""
VERIFY_IMAGES=false
USE_PYTHON=false

step_done() {
    local step="$1"
    if [[ -n "$PROGRESS_FILE" ]] && grep -q "^${step}$" "$PROGRESS_FILE" 2>/dev/null; then
        return 0
    fi
    return 1
}

mark_step_done() {
    local step="$1"
    if [[ -n "$PROGRESS_FILE" ]]; then
        echo "$step" >> "$PROGRESS_FILE"
    fi
    COMPLETED_STEPS="$COMPLETED_STEPS $step"
}

run_step() {
    local step="$1"
    local desc="$2"
    shift 2

    if step_done "$step"; then
        log_info "$desc: 已完成（跳过）"
    else
        "$@"
        mark_step_done "$step"
    fi
}

rollback() {
    log_error "安装失败，执行回滚..."
    for step in $COMPLETED_STEPS; do
        case "$step" in
            service_up)     service_down "$INSTALL_DIR" "$INSTALL_DIR/.env" 2>/dev/null || true ;;
            copy_files)     rm -rf "$INSTALL_DIR/conf" "$INSTALL_DIR/external-compose" "$INSTALL_DIR/docker-images" 2>/dev/null || true ;;
            prepare_dir)    rm -rf "$INSTALL_DIR" 2>/dev/null || true ;;
        esac
    done
    log_error "回滚完成，请检查错误后重试"
}

trap rollback ERR

show_help() {
    cat << EOF
Fit2Cloud 2.0 安装脚本

用法: install.sh [选项]

选项:
    -h, --help              显示帮助
    -s, --silent            静默安装（无交互，交互处自动取默认值）
    -d, --dir DIR           安装目录 (默认: /opt/fit2cloud)
    -e, --env FILE          安装期配置文件 (默认: install.env)
    -r, --runtime-env FILE  运行期配置文件 (默认: runtime.env)
    --no-minio              不安装 MinIO
    --no-telegraf           不安装 Telegraf
    --with-nginx            安装 Nginx 反向代理
    --force-reinstall       忽略已完成的步骤，强制重新安装
    --verify-images         全量 md5 校验 Docker 镜像包（默认仅做轻量校验）
    --python                使用 Python 实验版本安装（需安装包已包含 scripts_py/）

配置文件分层:
    install.env   安装期变量：部署模式、安装路径、访问地址、集群、组件开关
    runtime.env   运行期变量：中间件连接/密码、Nginx、性能、日志、备份
    .env          安装时自动合并生成，运行期唯一契约，请勿手改

示例:
    install.sh                        # 交互式安装
    install.sh -s                     # 静默安装
    install.sh -s -d /data/fit2cloud  # 静默安装到指定目录
    install.sh -s --no-minio          # 静默安装，跳过 MinIO
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)       show_help; exit 0 ;;
            -s|--silent)     SILENT_MODE=true; shift ;;
            -d|--dir)        INSTALL_DIR="$2"; shift 2 ;;
            -e|--env)        INSTALL_ENV="$2"; shift 2 ;;
            -r|--runtime-env) RUNTIME_ENV="$2"; shift 2 ;;
            --no-minio)      set_env_value CE_EXTERNAL_MINIO true "$INSTALL_ENV"; shift ;;
            --no-telegraf)   set_env_value CE_INSTALL_TELEGRAF false "$INSTALL_ENV"; shift ;;
            --with-nginx)    WITH_NGINX=true; shift ;;
            --force-reinstall) FORCE_REINSTALL=true; shift ;;
            --verify-images) VERIFY_IMAGES=true; shift ;;
            --python) USE_PYTHON=true; shift ;;
            *)               log_error "未知参数: $1"; show_help; exit 1 ;;
        esac
    done
}

load_env() {
    if [[ ! -f "$INSTALL_ENV" ]]; then
        if [[ -f "$FIT2CLOUD_DIR/.env" ]]; then
            INSTALL_ENV="$FIT2CLOUD_DIR/.env"
            log_warn "未找到 install.env，兼容使用旧版 .env: $INSTALL_ENV"
        else
            log_error "安装期配置不存在: $INSTALL_ENV"
            log_info "请先创建: cp install.env.example install.env && cp runtime.env.example runtime.env"
            exit 1
        fi
    fi

    if [[ ! -f "$RUNTIME_ENV" ]]; then
        log_warn "运行期配置不存在: $RUNTIME_ENV（中间件等参数将使用内置默认值）"
    fi

    CE_INSTALL_PATH=$(get_env_value CE_INSTALL_PATH "/opt" "$INSTALL_ENV")
    CE_ACCESS_PORT=$(get_env_value CE_ACCESS_PORT "80" "$INSTALL_ENV")
    CE_ACCESS_IP=$(get_env_value CE_ACCESS_IP "" "$INSTALL_ENV")
    # 渲染模板对 CE_ACCESS_IP 是 required：留空时在渲染前自动探测并写回安装期配置，
    # 避免渲染阶段因缺值直接失败
    if [[ -z "$CE_ACCESS_IP" ]]; then
        CE_ACCESS_IP=$(get_local_ip) || CE_ACCESS_IP=""
        if [[ -n "$CE_ACCESS_IP" ]]; then
            set_env_value CE_ACCESS_IP "$CE_ACCESS_IP" "$INSTALL_ENV"
            log_info "访问 IP 未配置，自动检测: $CE_ACCESS_IP"
        else
            log_warn "无法自动检测本机 IP，请手动在 $INSTALL_ENV 中配置 CE_ACCESS_IP"
        fi
    fi
    IMAGE_ADDRESS=$(get_env_value IMAGE_ADDRESS "registry.fit2cloud.com/north" "$INSTALL_ENV")
    PLATFORM=$(get_env_value PLATFORM "amd64" "$INSTALL_ENV")

    INSTALL_DIR="${INSTALL_DIR:-${CE_INSTALL_PATH}/fit2cloud}"

    # 归一化：-d /data 视为安装根目录，实际安装到 /data/fit2cloud
    # （compose 卷挂载使用 CE_INSTALL_PATH/fit2cloud，必须与 INSTALL_DIR 一致）
    if [[ "$(basename "$INSTALL_DIR")" != "fit2cloud" ]]; then
        INSTALL_DIR="$INSTALL_DIR/fit2cloud"
    fi

    # 集群模式自动配置
    local ce_mode=$(get_env_value CE_MODE "standalone" "$INSTALL_ENV")
    if [[ "$ce_mode" == "cluster" ]]; then
        configure_cluster
    fi
}

configure_cluster() {
    local cluster_nodes=$(get_env_value CE_CLUSTER_NODES "" "$INSTALL_ENV")
    local cluster_midware_node=$(get_env_value CE_CLUSTER_MIDWARE_NODE "node1" "$INSTALL_ENV")
    local cluster_start_mw=$(get_env_value CE_CLUSTER_START_MW "true" "$INSTALL_ENV")
    local cluster_node_id=$(get_env_value CE_CLUSTER_NODE_ID "" "$INSTALL_ENV")

    if [[ -z "$cluster_nodes" ]]; then
        log_error "集群模式需要配置 CE_CLUSTER_NODES"
        exit 1
    fi

    if [[ -z "$cluster_node_id" ]]; then
        log_error "集群模式需要配置 CE_CLUSTER_NODE_ID"
        exit 1
    fi

    # 自动生成 Eureka 地址
    IFS=',' read -ra nodes <<< "$cluster_nodes"
    local eureka_list=""
    for node in "${nodes[@]}"; do
        local ip="${node#*:}"
        [[ -n "$eureka_list" ]] && eureka_list+=","
        eureka_list+="${ip}"
    done
    set_env_value CE_EUREKA_SERVERS "$eureka_list" "$INSTALL_ENV"

    # 非中间件节点自动外部化
    if [[ "$cluster_start_mw" != "true" ]]; then
        local mw_ip=""
        for node in "${nodes[@]}"; do
            local name="${node%%:*}"
            if [[ "$name" == "$cluster_midware_node" ]]; then
                mw_ip="${node#*:}"
                break
            fi
        done

        if [[ -z "$mw_ip" ]]; then
            log_error "未找到中间件节点 $cluster_midware_node 的 IP"
            exit 1
        fi

        for mw in MYSQL REDIS INFLUXDB RABBITMQ MINIO KEYCLOAK ANSIBLE; do
            set_env_value "CE_EXTERNAL_$mw" "true" "$INSTALL_ENV"
        done

        set_env_value CE_MYSQL_HOST "$mw_ip" "$INSTALL_ENV"
        set_env_value CE_REDIS_HOST "$mw_ip" "$INSTALL_ENV"
        set_env_value CE_INFLUXDB_URL "http://${mw_ip}:8086" "$INSTALL_ENV"
        set_env_value CE_RABBITMQ_HOST "$mw_ip" "$INSTALL_ENV"
        set_env_value CE_MINIO_ENDPOINT "http://${mw_ip}:9000" "$INSTALL_ENV"
        set_env_value CE_KEYCLOAK_URL "http://${mw_ip}:8080/auth" "$INSTALL_ENV"
        set_env_value CE_ANSIBLE_HOST "http://${mw_ip}:8000" "$INSTALL_ENV"

        log_info "集群模式: 已配置外部中间件指向 $cluster_midware_node ($mw_ip)"
    else
        log_info "集群模式: 当前节点启动中间件"
    fi
}

show_install_info() {
    print_title "Fit2Cloud 2.0 安装信息"

    log_info "安装目录:   $INSTALL_DIR"
    log_info "镜像地址:   $IMAGE_ADDRESS"
    log_info "平台架构:   $PLATFORM"
    log_info "访问端口:   $CE_ACCESS_PORT"
    log_info "静默模式:   $SILENT_MODE"

    print_subtitle "中间件配置"
    for item in "CE_EXTERNAL_MYSQL:MySQL" "CE_EXTERNAL_REDIS:Redis" "CE_EXTERNAL_MINIO:MinIO" "CE_EXTERNAL_INFLUXDB:InfluxDB" "CE_EXTERNAL_RABBITMQ:RabbitMQ"; do
        local key="${item%%:*}"
        local name="${item##*:}"
        local val=$(get_env_value "$key" "false" "$INSTALL_ENV")
        if [[ "$val" == "true" ]]; then
            log_info "$name: 外部"
        else
            log_info "$name: 内置"
        fi
    done

    echo
}

check_environment() {
    print_title "环境检查"

    if [[ "$(id -u)" -ne 0 ]]; then
        log_warn "建议使用 root 用户安装"
    fi

    check_system_all || exit 1

    if ! check_docker; then
        log_warn "Docker 未安装，安装过程中将尝试自动安装"
    fi

    if ! check_docker_compose; then
        log_error "docker-compose 未安装，请先安装"
        exit 1
    fi

    local has_warn=false
    local mw_check_list="CE_EXTERNAL_MYSQL:check_mysql:MySQL CE_EXTERNAL_REDIS:check_redis:Redis CE_EXTERNAL_KEYCLOAK:check_keycloak:Keycloak CE_EXTERNAL_ANSIBLE:check_ansible:Ansible"

    for item in $mw_check_list; do
        local key="${item%%:*}"
        local rest="${item#*:}"
        local func="${rest%%:*}"
        local name="${rest##*:}"
        local val=$(get_env_value "$key" "false" "$INSTALL_ENV")
        if [[ "$val" != "true" ]]; then
            $func || { log_warn "$name 检查异常"; has_warn=true; }
        fi
    done

    if ! check_port "$CE_ACCESS_PORT"; then
        log_error "端口 $CE_ACCESS_PORT 已被占用"
        exit 1
    fi

    local ce_mode=$(get_env_value CE_MODE "standalone" "$INSTALL_ENV")
    if [[ "$ce_mode" == "cluster" ]]; then
        local cluster_ports="6602 6608 6610 6605 6604 6603 6001 5920"
        for p in $cluster_ports; do
            if ! check_port "$p"; then
                log_warn "集群模式端口 $p 已被占用"
                has_warn=true
            fi
        done
    fi

    if [[ "$has_warn" == "true" ]]; then
        log_warn "环境检查完成（存在警告，不影响安装）"
    else
        log_success "环境检查通过"
    fi
}

prepare_install_dir() {
    print_title "准备安装目录"

    local dirs=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/conf"
        "$INSTALL_DIR/conf/mysql"
        "$INSTALL_DIR/conf/redis"
        "$INSTALL_DIR/conf/minio"
        "$INSTALL_DIR/conf/telegraf"
        "$INSTALL_DIR/conf/keycloak"
        "$INSTALL_DIR/logs"
        "$INSTALL_DIR/data/mysql"
        "$INSTALL_DIR/data/redis"
        "$INSTALL_DIR/data/influxdb"
        "$INSTALL_DIR/data/rabbitmq"
        "$INSTALL_DIR/data/minio"
        "$INSTALL_DIR/data/plugins"
        "$INSTALL_DIR/git"
        "$INSTALL_DIR/sftp/sftpuser/upload"
        "$INSTALL_DIR/middleware_init"
        "$INSTALL_DIR/backup"
    )
    for dir in "${dirs[@]}"; do
        ensure_dir "$dir"
    done

    log_success "安装目录准备完成"
}

copy_files() {
    print_title "复制安装文件"

    for sub in conf external-compose docker-images tools data bin; do
        if [[ -d "$FIT2CLOUD_DIR/$sub" ]]; then
            cp -r "$FIT2CLOUD_DIR/$sub" "$INSTALL_DIR/"
        fi
    done

    # 包清单（存在才复制，供 verify_package 校验）
    if [[ -f "$FIT2CLOUD_DIR/manifest.txt" ]]; then
        cp -f "$FIT2CLOUD_DIR/manifest.txt" "$INSTALL_DIR/"
    fi

    # 安装期/运行期配置分开存放；.env 为合并产物（运行期唯一契约）
    if [[ -f "$INSTALL_DIR/install.env" ]]; then
        log_warn "已存在 $INSTALL_DIR/install.env，保留现有配置（新配置模板: $INSTALL_ENV）"
    else
        cp "$INSTALL_ENV" "$INSTALL_DIR/install.env"
        log_info "install.env → $INSTALL_DIR/install.env"
    fi
    if [[ -f "$RUNTIME_ENV" ]]; then
        if [[ -f "$INSTALL_DIR/runtime.env" ]]; then
            log_warn "已存在 $INSTALL_DIR/runtime.env，保留现有配置（新配置模板: $RUNTIME_ENV）"
        else
            cp "$RUNTIME_ENV" "$INSTALL_DIR/runtime.env"
            log_info "runtime.env → $INSTALL_DIR/runtime.env"
        fi
    fi

    # 合并生成运行期契约 .env（后者覆盖前者）：
    #   打包 .env → 两个 example（兜底新版本新增变量的默认值）→ 用户 install.env / runtime.env
    merge_env_files "$INSTALL_DIR/.env" "$FIT2CLOUD_DIR/.env" \
        "$FIT2CLOUD_DIR/runtime.env.example" "$FIT2CLOUD_DIR/install.env.example" \
        "$INSTALL_DIR/runtime.env" "$INSTALL_DIR/install.env"
    # 安装路径用实际安装目录覆盖（compose 卷挂载依赖它）
    set_env_value CE_INSTALL_PATH "$(dirname "$INSTALL_DIR")" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env" 2>/dev/null || true
    log_info ".env → $INSTALL_DIR/.env (合并生成, 权限 600)"

    log_success "安装文件复制完成"
}

verify_package() {
    local manifest="$INSTALL_DIR/manifest.txt"
    if [[ ! -f "$manifest" ]]; then
        log_warn "未找到 manifest.txt，跳过包完整性校验（旧版本安装包）"
        return 0
    fi

    print_title "校验安装包完整性"

    local pkg_version=$(grep '^version=' "$manifest" | cut -d= -f2-)
    local pkg_platform=$(grep '^platform=' "$manifest" | cut -d= -f2-)
    log_info "包版本: $pkg_version  平台: $pkg_platform"

    if [[ "$VERIFY_IMAGES" == "true" ]]; then
        log_info "全量 md5 校验 Docker 镜像包（大包耗时较长）..."
        local image_md5s
        image_md5s=$(grep -E '^[0-9a-f]{32}  ' "$manifest" || true)
        if [[ -z "$image_md5s" ]]; then
            log_warn "manifest 中无镜像 md5 记录，跳过全量校验"
            return 0
        fi
        local tmp_check; tmp_check=$(mktemp)
        echo "$image_md5s" > "$tmp_check"
        if (cd "$INSTALL_DIR/docker-images" && md5sum -c --quiet "$tmp_check"); then
            rm -f "$tmp_check"
            log_success "镜像 md5 全量校验通过"
        else
            rm -f "$tmp_check"
            log_error "镜像 md5 校验失败，安装包已损坏，请重新下载"
            return 1
        fi
    else
        log_info "轻量校验模式（--verify-images 可启用全量 md5 校验）"
        local image_tars missing=0
        image_tars=$(grep -E '^[0-9a-f]{32}  ' "$manifest" | awk '{print $2}')
        for f in $image_tars; do
            if [[ ! -s "$INSTALL_DIR/docker-images/$f" ]]; then
                log_error "镜像文件缺失或为空: $f"
                missing=$((missing + 1))
            fi
        done
        if [[ $missing -gt 0 ]]; then
            log_error "共 $missing 个镜像文件缺失，安装包不完整，请重新下载"
            return 1
        fi
        log_success "镜像文件存在性校验通过"
    fi
}

load_docker_images() {
    local images_dir="$INSTALL_DIR/docker-images"
    if [[ ! -d "$images_dir" ]] || [[ -z "$(ls -A "$images_dir" 2>/dev/null)" ]]; then
        log_warn "docker-images 目录为空，跳过镜像加载"
        return 0
    fi

    print_title "加载 Docker 镜像"

    local total=$(ls "$images_dir"/*.tar 2>/dev/null | wc -l)
    local current=0
    for tar_file in "$images_dir"/*.tar; do
        [[ ! -f "$tar_file" ]] && continue
        current=$((current + 1))
        local name=$(basename "$tar_file" .tar)
        log_info_inline "[$current/$total] $name"
        docker load -i "$tar_file" >/dev/null 2>&1
        log_ok
    done

    log_success "Docker 镜像加载完成 ($current/$total)"

    # 对账：compose 期望的镜像必须全部加载成功，缺一个都不允许继续安装
    local expected_images missing=0
    expected_images=$(get_all_images "$INSTALL_DIR/.env")
    for img in $expected_images; do
        if ! docker image inspect "$img" >/dev/null 2>&1; then
            log_error "镜像缺失: $img"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -gt 0 ]]; then
        log_error "共缺失 $missing 个镜像，安装包可能损坏（可用 --verify-images 全量校验排查）"
        return 1
    fi
    log_success "镜像对账通过: $(echo "$expected_images" | wc -w | tr -d ' ') 个全部就绪"
}

do_render_config() {
    print_title "渲染配置文件"

    # 渲染：runtime.env 为基础，install.env 覆盖其中的部署级变量（如 CE_ACCESS_IP/CE_MODE）
    do_render "$INSTALL_DIR/runtime.env,$INSTALL_DIR/install.env" "$FIT2CLOUD_DIR/conf" "$INSTALL_DIR/conf"

    log_success "配置文件渲染完成"
}

install_middleware() {
    print_title "安装中间件"

        # 供 source 的中间件脚本读写（shellcheck 静态不可见）
        # shellcheck disable=SC2034
        ENV_FILE="$INSTALL_DIR/.env"

    local ce_external_minio=$(get_env_value CE_EXTERNAL_MINIO "false" "$INSTALL_DIR/.env")
    if [[ "$ce_external_minio" == "true" ]]; then
        log_info "MinIO: 跳过（使用外部服务）"
    else
        install_minio
        configure_minio
    fi

    local ce_install_telegraf=$(get_env_value CE_INSTALL_TELEGRAF "true" "$INSTALL_DIR/.env")
    if [[ "$ce_install_telegraf" != "true" ]]; then
        log_info "Telegraf: 跳过"
    else
        install_telegraf
        configure_telegraf
    fi

    local ce_install_nginx=$(get_env_value CE_INSTALL_NGINX "false" "$INSTALL_DIR/.env")
    if [[ "$WITH_NGINX" == "true" || "$ce_install_nginx" == "true" ]]; then
        install_nginx
        configure_nginx
    fi

    local mw_list="mysql redis influxdb rabbitmq keycloak ansible"
    for mw in $mw_list; do
        install_$mw
        configure_$mw
    done
}

configure_access_address() {
    print_title "配置访问地址"

    local ip_addr="$CE_ACCESS_IP"
    if [[ -z "$ip_addr" ]]; then
        ip_addr=$(get_local_ip)
    fi

    if [[ -n "$ip_addr" ]]; then
        set_env_value CE_ACCESS_IP "$ip_addr" "$INSTALL_DIR/.env"
        log_info "访问地址: http://$ip_addr:$CE_ACCESS_PORT"
    else
        log_warn "无法获取本机 IP，请手动配置 CE_ACCESS_IP"
    fi
}

wait_for_healthy() {
    print_subtitle "等待服务启动..."

    local max_wait=$(get_env_value CE_HEALTHY_TIMEOUT "600" "$INSTALL_DIR/.env")
    local elapsed=0
    local interval=10

    # 期望服务数以 compose 配置为准：个别容器 crash-loop（restarting）不计入 running，
    # 若只按 running 数量判断会漏掉它而误报健康
    local expected=0
    local compose_cmd
    compose_cmd=$(_get_compose_cmd "$INSTALL_DIR" "$INSTALL_DIR/.env" 2>/dev/null) || compose_cmd=""
    if [[ -n "$compose_cmd" ]]; then
        local profile_args="$(_get_profile_args "$INSTALL_DIR/.env")"
        expected=$($compose_cmd $profile_args config --services 2>/dev/null | wc -l | tr -d ' ')
    fi

    while [[ $elapsed -lt $max_wait ]]; do
        local total unhealthy starting restarting
        total=$(docker ps --filter "name=fit2cloud" --filter "status=running" -q 2>/dev/null | wc -l)
        unhealthy=$(docker ps --filter "name=fit2cloud" --filter "health=unhealthy" --filter "status=running" -q 2>/dev/null | wc -l)
        starting=$(docker ps --filter "name=fit2cloud" --filter "health=starting" --filter "status=running" -q 2>/dev/null | wc -l)
        restarting=$(docker ps -a --filter "name=fit2cloud" --filter "status=restarting" -q 2>/dev/null | wc -l)

        if [[ $unhealthy -eq 0 && $starting -eq 0 && $restarting -eq 0 ]] \
            && { [[ $expected -eq 0 && $total -gt 0 ]] || [[ $total -ge $expected ]]; }; then
            log_success "所有服务已健康运行 ($total/$expected)"
            return 0
        fi

        log_info "等待服务启动... (运行: $total/${expected:-?}, 异常: $((unhealthy + restarting)), 已等待 ${elapsed}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_error "部分服务未在 ${max_wait}s 内变为 healthy，请手动检查: docker ps"
    return 1
}

show_completion_info() {
    print_title "安装完成"

    local ip_addr=$(get_env_value CE_ACCESS_IP "" "$INSTALL_DIR/.env")
    if [[ -z "$ip_addr" ]]; then
        ip_addr=$(get_local_ip)
    fi

    local admin_user=$(get_env_value CE_ADMIN_USERNAME "admin" "$INSTALL_DIR/.env")

    cat << EOF

============================================================================
  Fit2Cloud 2.0 安装完成！
============================================================================
  访问地址:  http://${ip_addr}:$CE_ACCESS_PORT
  (服务启动约需 5 分钟，请耐心等待)

  管理员账号:  $admin_user
  管理员密码:  ******（请查看 $INSTALL_DIR/.env 中 CE_ADMIN_PASSWORD）

  安装目录:  $INSTALL_DIR
  配置文件:  $INSTALL_DIR/.env
  日志目录:  $INSTALL_DIR/logs

  管理命令:  $INSTALL_DIR/bin/fit2cloud/standalone/f2cctl
============================================================================

EOF
}

ensure_docker_network() {
    local network_name=$(get_env_value CE_NETWORK_NAME "cmp-network" "$INSTALL_DIR/.env")
    if ! docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network_name}$"; then
        log_info "创建 Docker 网络: $network_name"
        docker network create "$network_name" >/dev/null 2>&1 || true
    fi
}

prepare_runtime_secrets() {
    # 渲染前预生成运行期密钥并写入 runtime.env 与合并 .env：
    # 否则密钥在 middleware 阶段才生成，渲染早已完成，conf 与实际凭据会不一致
    local env_f="$INSTALL_DIR/.env"

    if [[ "$(get_env_value CE_EXTERNAL_MINIO "false" "$env_f")" != "true" ]] \
        && [[ -z "$(get_env_value CE_MINIO_ACCESS_KEY "" "$env_f")" ]]; then
        local ak sk bucket
        ak=$(generate_random_key 20)
        sk=$(generate_random_key 40)
        bucket=$(get_env_value CE_MINIO_DEFAULT_BUCKET "" "$env_f")
        [[ -z "$bucket" ]] && bucket="cmp"
        for target in "$INSTALL_DIR/runtime.env" "$env_f"; do
            set_env_value CE_MINIO_ACCESS_KEY "$ak" "$target"
            set_env_value CE_MINIO_SECRET_KEY "$sk" "$target"
            set_env_value CE_MINIO_DEFAULT_BUCKET "$bucket" "$target"
        done
        log_info "已预生成 MinIO AccessKey/SecretKey（写入 runtime.env）"
    fi
}

deploy_cli_tools() {
    # 部署 f2cctl 命令：生成固定路径的 shim（f2cctl 内部按自身位置解析安装目录，
    # 直接拷贝到 /usr/bin 会解析成 /scripts，必须以 shim 方式转发到实际路径）
    local f2cctl_src="$INSTALL_DIR/bin/fit2cloud/standalone/f2cctl"
    if [[ ! -f "$f2cctl_src" ]]; then
        log_warn "未找到 f2cctl，跳过命令部署: $f2cctl_src"
        return 0
    fi
    chmod +x "$f2cctl_src" 2>/dev/null || true
    cat > /usr/bin/f2cctl <<EOF
#!/bin/bash
# Fit2Cloud 2.0 管理命令（install.sh 生成）
exec $f2cctl_src "\$@"
EOF
    chmod +x /usr/bin/f2cctl
    log_info "已部署管理命令: /usr/bin/f2cctl → $f2cctl_src"
}

install_systemd() {
    if [[ ! -d /etc/systemd/system ]]; then
        return 0
    fi

    local unit_src="$INSTALL_DIR/bin/fit2cloud/standalone/fit2cloud.systemd"
    if [[ ! -f "$unit_src" ]]; then
        return 0
    fi

    local install_path=$(get_env_value CE_INSTALL_PATH "/opt" "$INSTALL_DIR/.env")
    local unit_file="/etc/systemd/system/fit2cloud.service"

    cp -f "$unit_src" "$unit_file"
    sed -i -E "s|/opt/fit2cloud|${install_path}/fit2cloud|g" "$unit_file"

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable fit2cloud.service >/dev/null 2>&1 || true
    log_info "已安装 systemd 服务 (fit2cloud.service)"
}

do_install() {
    local start_time=$(date +%s)

    PROGRESS_FILE="$INSTALL_DIR/.install-progress"

    if [[ "$FORCE_REINSTALL" == "true" ]]; then
        rm -f "$PROGRESS_FILE"
        log_info "强制重新安装模式"
    elif [[ -f "$PROGRESS_FILE" ]]; then
        log_info "检测到之前的安装进度，将跳过已完成的步骤"
    fi

    check_environment

    if ! check_docker; then
        run_step "install_docker" "Docker 安装" install_docker
    fi

    if ! check_docker_compose; then
        log_error "docker-compose 未安装且无法自动安装，请手动安装后重试"
        return 1
    fi

    run_step "prepare_dir" "准备安装目录" prepare_install_dir
    run_step "copy_files" "复制安装文件" copy_files
    verify_package
    run_step "load_images" "加载 Docker 镜像" load_docker_images
    run_step "prepare_secrets" "生成运行期密钥" prepare_runtime_secrets
    run_step "render_config" "渲染配置文件" do_render_config

    ensure_docker_network

    run_step "middleware" "安装中间件" install_middleware
    run_step "service_up" "启动服务" service_up "$INSTALL_DIR" "$INSTALL_DIR/.env"

    wait_for_healthy
    configure_access_address
    install_systemd
    deploy_cli_tools

    echo "COMPLETE" > "$PROGRESS_FILE"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_info "安装耗时: $((duration / 60))分$((duration % 60))秒"

    show_completion_info
}

main() {
    parse_args "$@"
    load_env

    # Python 实验版本入口
    if [[ "${USE_PYTHON:-false}" == "true" ]]; then
        local scripts_py="$FIT2CLOUD_DIR/scripts_py/install.py"
        if [[ ! -f "$scripts_py" ]]; then
            log_error "未找到 Python 安装脚本: $scripts_py"
            log_info "请确保安装包包含了 scripts_py/ 目录（构建时使用 --with-python）"
            exit 1
        fi
        log_info "使用 Python 实验版本安装..."
        log_info "Python 脚本: $scripts_py"
        echo
        python3 "$scripts_py" --dir "$INSTALL_DIR" \
            --install-env "$INSTALL_ENV" \
            --runtime-env "$RUNTIME_ENV" \
            --silent \
            "$@"
        exit $?
    fi

    if [[ "$SILENT_MODE" == "true" ]]; then
        do_install
    else
        show_install_info
        echo
        read -r -p "是否继续安装？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
        do_install
    fi
}

main "$@"
