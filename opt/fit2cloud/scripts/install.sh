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
# 命令行开关默认值（set -u 下必须初始化）
SILENT_MODE=false
CURRENT_STEP_DESC=""   # 当前执行的安装步骤（失败时提示定位用）
INSTALL_DIR=""
WITH_NGINX=false
FORCE_REINSTALL=false

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
        CURRENT_STEP_DESC="$desc"
        log_info "==> $desc"
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
    log_error "回滚完成。失败步骤: ${CURRENT_STEP_DESC:-未知}"
    log_error "完整日志: ${LOG_FILE:-（未启用）}"
    log_info "重新执行 bash install.sh 将自动跳过已完成的步骤，从失败处继续安装"
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
            *)               log_error "未知参数: $1"; show_help; exit 1 ;;
        esac
    done
}

ensure_install_config() {
    # 免配置：配置文件不存在时按 example 自动生成，解压后直接 bash install.sh 即可安装
    if [[ ! -f "$INSTALL_ENV" ]]; then
        if [[ -f "$FIT2CLOUD_DIR/install.env.example" ]]; then
            cp "$FIT2CLOUD_DIR/install.env.example" "$INSTALL_ENV"
            # 打包期写入的 .env（镜像仓库/平台/镜像 tag/中间件镜像）优先于 example 默认值，
            # 保证安装侧镜像名与离线镜像包 docker load 进来的名称一致
            if [[ -f "$FIT2CLOUD_DIR/.env" ]]; then
                local key value
                while IFS='=' read -r key value; do
                    key="${key//[[:space:]]/}"
                    [[ -z "$key" || "$key" == \#* ]] && continue
                    set_env_value "$key" "$value" "$INSTALL_ENV"
                done < "$FIT2CLOUD_DIR/.env"
            fi
            log_info "未找到 install.env，已按默认值自动生成: $INSTALL_ENV"
        elif [[ -f "$FIT2CLOUD_DIR/.env" ]]; then
            INSTALL_ENV="$FIT2CLOUD_DIR/.env"
            log_warn "未找到 install.env 与 example，兼容使用打包 .env: $INSTALL_ENV"
        else
            log_error "安装期配置不存在: $INSTALL_ENV"
            exit 1
        fi
    fi

    if [[ ! -f "$RUNTIME_ENV" && -f "$FIT2CLOUD_DIR/runtime.env.example" ]]; then
        cp "$FIT2CLOUD_DIR/runtime.env.example" "$RUNTIME_ENV"
        log_info "未找到 runtime.env，已按默认值自动生成: $RUNTIME_ENV"
    fi
}

load_env() {
    ensure_install_config

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
    # 以下两个全局变量被 render.sh / service.sh（source 引入）消费，shellcheck 单文件视角报未使用
    # shellcheck disable=SC2034
    IMAGE_ADDRESS=$(get_env_value IMAGE_ADDRESS "registry.fit2cloud.com/north" "$INSTALL_ENV")
    # shellcheck disable=SC2034
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

    # scripts 必须一并复制：装机后的 f2cctl / init.d 脚本 / 扩展模块脚本都按
    # <安装目录>/scripts/*.sh 加载库，缺失会导致 f2cctl 启动即报文件不存在
    for sub in conf external-compose docker-images tools data bin scripts; do
        if [[ -d "$FIT2CLOUD_DIR/$sub" ]]; then
            cp -r "$FIT2CLOUD_DIR/$sub" "$INSTALL_DIR/"
        fi
    done
    chmod -R a+x "$INSTALL_DIR/bin" "$INSTALL_DIR/scripts" 2>/dev/null || true

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

# md5 校验失败时自动重新下载安装包并重新解压（无感知修复）
# 依赖打包时写入的 fit2cloud/package-source.url；不存在则无法自修复，回退为人工下载
repair_package_from_source() {
    local url_file="$FIT2CLOUD_DIR/package-source.url"
    if [[ ! -s "$url_file" ]]; then
        log_warn "未找到 $url_file，无法自动重新下载（请手动重新下载安装包）"
        return 1
    fi
    local url
    url=$(head -1 "$url_file")
    log_warn "镜像 md5 校验失败，自动重新下载安装包..."
    log_info "下载地址: $url"

    local tmp_tar tmp_md5
    tmp_tar=$(mktemp /tmp/fit2cloud-package.XXXXXX)
    tmp_md5="${tmp_tar}.md5"
    if ! download_file "$url" "$tmp_tar"; then
        rm -f "$tmp_tar" "$tmp_md5"
        log_error "重新下载失败"
        return 1
    fi

    # 下载侧的整包 md5（内容格式 "md5: <hash>"），存在则先验证再解压，避免二次损坏
    local expected="" actual
    if download_file "${url}.md5" "$tmp_md5" 2>/dev/null; then
        expected=$(sed -n 's/^md5:[[:space:]]*//p' "$tmp_md5" | head -1)
    fi
    if [[ -n "$expected" ]]; then
        actual=$(md5sum "$tmp_tar" | awk '{print $1}')
        if [[ "$actual" != "$expected" ]]; then
            rm -f "$tmp_tar" "$tmp_md5"
            log_error "重新下载后 md5 仍不一致（可能源文件损坏）"
            return 1
        fi
    fi

    # 重新解压覆盖回原解压目录（installer/ 上级），fit2cloud 目录布局不变
    local package_root
    package_root="$(dirname "$(dirname "$FIT2CLOUD_DIR")")"
    if ! tar -xf "$tmp_tar" -C "$package_root"; then
        rm -f "$tmp_tar" "$tmp_md5"
        log_error "重新解压失败"
        return 1
    fi
    rm -f "$tmp_tar" "$tmp_md5"
    log_success "安装包已重新下载并解压完成"
    return 0
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
            # 自动修复：重新下载安装包并重解压，然后复检一次
            if repair_package_from_source; then
                echo "$image_md5s" > "$tmp_check"
                if (cd "$INSTALL_DIR/docker-images" && md5sum -c --quiet "$tmp_check"); then
                    rm -f "$tmp_check"
                    log_success "镜像 md5 全量校验通过（已自动重新下载修复）"
                    return 0
                fi
            fi
            rm -f "$tmp_check"
            log_error "镜像 md5 校验失败，自动修复未成功，请手动重新下载安装包"
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
        # _get_compose_cmd 已包含 --env-file / --profile / -f 全局参数
        expected=$($compose_cmd config --services 2>/dev/null | wc -l | tr -d ' ')
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
    local protocol=$(get_env_value CE_ACCESS_PROTOCOL "http" "$INSTALL_DIR/.env")
    local admin_user=$(get_env_value CE_ADMIN_USERNAME "admin" "$INSTALL_DIR/.env")

    cat << EOF

============================================================================
  Fit2Cloud 2.0 安装完成！
============================================================================
  访问地址:  ${protocol}://${ip_addr}:$CE_ACCESS_PORT

  服务启动约需 5 分钟，期间可用以下命令查看进度:
      f2cctl status
      f2cctl logs --tail=50
  如访问不通，请检查防火墙/安全组是否已放行端口 $CE_ACCESS_PORT

  管理员账号:  $admin_user
  管理员密码:  ******（请查看 $INSTALL_DIR/.env 中 CE_ADMIN_PASSWORD）

  常用运维命令（已部署到 /usr/bin/f2cctl）:
      f2cctl start|stop|restart [服务名]
      f2cctl backup              # 备份

  安装目录:  $INSTALL_DIR
  配置文件:  $INSTALL_DIR/.env
  日志目录:  $INSTALL_DIR/logs
  安装日志:  ${LOG_FILE:-(未启用)}

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
    cat > /usr/bin/f2cctl << EOF
#!/bin/bash
# Fit2Cloud 2.0 管理命令（install.sh 生成）
exec "$f2cctl_src" "\$@"
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
    replace_in_file "$unit_file" "s|/opt/fit2cloud|$(escape_sed_replacement "$install_path")/fit2cloud|g"

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

# 交互提问通用函数：说明文字 + 带默认值提示 + 可选校验器（返回非 0 则重问）
# 值通过 stdout 返回；read 的提示语走 stderr，不会污染捕获
ask_value() {
    local desc="$1" current="$2" validator="${3:-}" input
    while :; do
        read -r -p "${desc} [${current}]: " input || input=""
        input="${input:-$current}"
        if [[ -n "$validator" ]] && ! "$validator" "$input"; then
            log_warn "输入不合法，请重新输入"
            continue
        fi
        printf '%s\n' "$input"
        return 0
    done
}

validate_port()     { [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= $1 && $1 <= 65535 )); }
validate_ip()       { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
validate_abs_path() { [[ "$1" == /* ]]; }

# 环境快照（轻量只读，不做告警——正式检查在 do_install 的 check_environment）
show_environment_snapshot() {
    local cores mem_gb disk_avail_gb
    cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    mem_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")
    disk_avail_gb=$(df -BG "$CE_INSTALL_PATH" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}' || echo "?")
    log_info "CPU: ${cores} 核 | 内存: ${mem_gb} GB | 磁盘可用: ${disk_avail_gb} GB"
}

# 欢迎面板：交互模式与静默模式共用，展示包信息与将使用的配置
show_welcome() {
    local pkg_version
    pkg_version=$(head -1 "$FIT2CLOUD_DIR/conf/version" 2>/dev/null || echo "未知")
    local platform image_addr access_path access_port ext_minio

    platform=$(get_env_value PLATFORM "amd64" "$INSTALL_ENV")
    image_addr=$(get_env_value IMAGE_ADDRESS "-" "$INSTALL_ENV")
    access_path=$(get_env_value CE_INSTALL_PATH "/opt" "$INSTALL_ENV")
    access_port=$(get_env_value CE_ACCESS_PORT "80" "$INSTALL_ENV")
    ext_minio=$(get_env_value CE_EXTERNAL_MINIO "false" "$INSTALL_ENV")

    print_title "Fit2Cloud 2.0 离线安装"
    log_info "安装包版本: ${pkg_version}"
    log_info "目标平台:   ${platform}（镜像仓库: ${image_addr}）"
    log_info "配置文件:   ${INSTALL_ENV}"
    log_info "           ${RUNTIME_ENV}"
    log_info "环境快照:   $(get_local_ip 2>/dev/null || echo '?')"
    show_environment_snapshot
    echo
    log_info "将使用的默认配置（交互模式可逐项修改，静默模式直接使用）:"
    log_info "  安装路径:  ${access_path}/fit2cloud"
    local ip_show
    ip_show=$(get_env_value CE_ACCESS_IP "" "$INSTALL_ENV")
    log_info "  访问地址:  http://${ip_show:-(安装时自动检测本机IP)}:${access_port}"
    log_info "  MinIO:     $([[ "$ext_minio" == "true" ]] && echo "外部" || echo "内置")"
    echo
}

# 交互式配置向导：不传 -s 时提问核心配置项（与旧版安装向导一致），回车采用默认值
interactive_config() {
    local input minio_mode confirm

    echo
    log_info "开始配置（直接回车采用默认值；可随时 Ctrl+C 退出后编辑配置文件重跑）"

    # 部署模式
    log_info "部署模式: 1) standalone 单机（默认）  2) cluster 集群"
    while :; do
        read -r -p "请选择 [1]: " input || input=""
        input="${input:-1}"
        [[ "$input" == "1" || "$input" == "2" ]] && break
        log_warn "请输入 1 或 2"
    done
    if [[ "$input" == "2" ]]; then
        set_env_value CE_MODE cluster "$INSTALL_ENV"
        log_info "集群模式：中间件将按 install.env 中 CE_CLUSTER_* 配置部署"
    else
        set_env_value CE_MODE standalone "$INSTALL_ENV"
    fi

    # 安装路径（绝对路径校验 + 已存在提示）
    while :; do
        input=$(ask_value "安装路径（将以 <路径>/fit2cloud 作为安装目录）" \
            "$(get_env_value CE_INSTALL_PATH "/opt" "$INSTALL_ENV")" validate_abs_path)
        set_env_value CE_INSTALL_PATH "$input" "$INSTALL_ENV"
        if [[ -d "${input}/fit2cloud" ]]; then
            local yn
            read -r -p "目录 ${input}/fit2cloud 已存在，将复用并覆盖部署，是否继续？[Y/n]: " yn || yn=""
            [[ ! "$yn" =~ ^[Nn] ]] && break
        else
            break
        fi
    done

    # 访问端口 / IP
    set_env_value CE_ACCESS_PORT \
        "$(ask_value "访问端口" "$(get_env_value CE_ACCESS_PORT "80" "$INSTALL_ENV")" validate_port)" "$INSTALL_ENV"

    input=$(ask_value "访问 IP（已自动检测，多网卡时可指定）" "$CE_ACCESS_IP" validate_ip)
    if [[ "$input" != "$CE_ACCESS_IP" ]]; then
        CE_ACCESS_IP="$input"
        set_env_value CE_ACCESS_IP "$input" "$INSTALL_ENV"
    fi

    # MinIO 内置/外部
    read -r -p "是否使用外部 MinIO？[y/N]: " minio_mode || minio_mode=""
    if [[ "$minio_mode" =~ ^[Yy] ]]; then
        set_env_value CE_EXTERNAL_MINIO true "$INSTALL_ENV"
        while :; do
            input=$(ask_value "MinIO 访问地址（如 http://10.1.13.111:9001）" "" )
            [[ -n "$input" ]] && break
        done
        set_env_value CE_MINIO_ENDPOINT "$input" "$INSTALL_ENV"
        while :; do
            input=$(ask_value "MinIO accessKey" "")
            [[ -n "$input" ]] && break
            log_warn "accessKey 不能为空"
        done
        set_env_value CE_MINIO_ACCESS_KEY "$input" "$INSTALL_ENV"
        while :; do
            input=$(ask_value "MinIO secretKey" "")
            [[ -n "$input" ]] && break
            log_warn "secretKey 不能为空"
        done
        set_env_value CE_MINIO_SECRET_KEY "$input" "$INSTALL_ENV"
        while :; do
            input=$(ask_value "MinIO bucket" "")
            [[ -n "$input" ]] && break
            log_warn "bucket 不能为空"
        done
        set_env_value CE_MINIO_DEFAULT_BUCKET "$input" "$INSTALL_ENV"
    else
        set_env_value CE_EXTERNAL_MINIO false "$INSTALL_ENV"
    fi

    # Nginx
    read -r -p "是否安装 Nginx 反向代理？[y/N]: " input || input=""
    [[ "$input" =~ ^[Yy] ]] && set_env_value CE_INSTALL_NGINX true "$INSTALL_ENV"

    # 摘要确认
    echo
    log_info "---------- 配置摘要 ----------"
    log_info "安装路径: $(get_env_value CE_INSTALL_PATH "/opt" "$INSTALL_ENV")/fit2cloud"
    log_info "访问地址: $(get_env_value CE_ACCESS_PROTOCOL "http" "$INSTALL_ENV")://$(get_env_value CE_ACCESS_IP "-" "$INSTALL_ENV"):$(get_env_value CE_ACCESS_PORT "80" "$INSTALL_ENV")"
    log_info "部署模式: $(get_env_value CE_MODE "standalone" "$INSTALL_ENV")"
    ext_minio=$(get_env_value CE_EXTERNAL_MINIO "false" "$INSTALL_ENV")
    log_info "MinIO: $([[ "$ext_minio" == "true" ]] && echo "外部" || echo "内置")"
    nginx=$(get_env_value CE_INSTALL_NGINX "false" "$INSTALL_ENV")
    log_info "Nginx 反代: $([[ "$nginx" == "true" ]] && echo "安装" || echo "不安装")"
    log_info "配置文件: $INSTALL_ENV / $RUNTIME_ENV"
    echo
    read -r -p "确认以上配置并开始安装？(Y/n): " confirm || confirm=""
    if [[ "$confirm" =~ ^[Nn] ]]; then
        log_info "已取消。可修改 ${INSTALL_ENV} / ${RUNTIME_ENV} 后重新执行安装"
        exit 0
    fi
}

# 静默模式说明：明确告知使用默认值与自定义方式（不阻塞）
show_silent_banner() {
    log_info "静默安装模式：全部使用默认值（见上方面板），不进行交互确认"
    log_info "如需自定义（路径/端口/MinIO/集群等）：修改 ${INSTALL_ENV} 或 ${RUNTIME_ENV} 后重新执行安装"
}

main() {
    parse_args "$@"
    load_env

    # 安装全量日志留档（失败排查用；完成/失败提示中都会引用）
    LOG_FILE="/tmp/fit2cloud-install-$(date +%Y%m%d-%H%M%S).log"

    # 欢迎面板：展示包信息/环境快照/将使用的默认配置（两种模式共用）
    show_welcome
    log_info "安装日志: $LOG_FILE"

    # 交互模式：向导逐项确认；静默模式：提示默认值与自定义方式后直接安装
    if [[ "$SILENT_MODE" != "true" ]]; then
        interactive_config
    else
        show_silent_banner
        echo
    fi

    do_install
}

main "$@"
