#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$FIT2CLOUD_DIR/scripts/common.sh"
source "$FIT2CLOUD_DIR/scripts/service.sh"
source "$FIT2CLOUD_DIR/scripts/render.sh"

ENV_FILE="$FIT2CLOUD_DIR/.env"
INSTALLER_PATH=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
WORK_DIR="$INSTALLER_PATH/fit2cloud"

OLD_COMPOSE_DIR="$WORK_DIR/external-compose"
NEW_COMPOSE_DIR="$FIT2CLOUD_DIR/external-compose"

COMPLETED_STEPS=""
PROGRESS_FILE="$WORK_DIR/.upgrade-progress"
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-backup)  SKIP_BACKUP=true; shift ;;
        *)              log_error "未知参数: $1 (支持: --skip-backup)"; exit 1 ;;
    esac
done

rollback() {
    log_error "升级失败，执行回滚..."
    for step in $COMPLETED_STEPS; do
        case "$step" in
            service_down)     service_up "$WORK_DIR" "$ENV_FILE" 2>/dev/null || true ;;
            update_compose)   cp -rf "$OLD_COMPOSE_DIR.bak" "$OLD_COMPOSE_DIR" 2>/dev/null || true ;;
        esac
    done
    log_error "回滚完成，请检查错误后重试"
    exit 1
}

trap rollback ERR

mark_step_done() {
    local step="$1"
    echo "$step" >> "$PROGRESS_FILE"
    COMPLETED_STEPS="$COMPLETED_STEPS $step"
}

do_pre_upgrade_backup() {
    local backup_time=$(date "+%Y-%m-%d-%H-%M-%S")
    local backup_dir="$WORK_DIR/backup/pre-upgrade-$backup_time"
    ensure_dir "$backup_dir"
    log_info "备份 conf / data / external-compose → $backup_dir (data 目录大时耗时较长)"
    cp -rp "$WORK_DIR/conf" "$backup_dir/"
    if [[ -d "$WORK_DIR/data" ]]; then
        cp -rp "$WORK_DIR/data" "$backup_dir/"
    fi
    if [[ -d "$WORK_DIR/external-compose" ]]; then
        cp -rp "$WORK_DIR/external-compose" "$backup_dir/"
    fi
    log_success "升级前备份完成（服务已停止，数据一致）"
}

print_title "FIT2CLOUD 升级"

log_info "停止 FIT2CLOUD 服务..."
service_down "$WORK_DIR" "$ENV_FILE"
mark_step_done "service_down"

# 升级前备份（服务已停止，数据一致；镜像不备份——旧镜像仍在本地可用于回退）
if [[ "$SKIP_BACKUP" == "true" ]]; then
    log_warn "已跳过升级前备份 (--skip-backup)"
else
    do_pre_upgrade_backup
fi

log_info "更新 compose 文件..."
if [[ -d "$NEW_COMPOSE_DIR" ]]; then
    if [[ -d "$OLD_COMPOSE_DIR" ]]; then
        cp -rf "$OLD_COMPOSE_DIR" "$OLD_COMPOSE_DIR.bak"
    fi
    mkdir -p "$OLD_COMPOSE_DIR"
    cp -rf "$NEW_COMPOSE_DIR/"* "$OLD_COMPOSE_DIR/"
    mark_step_done "update_compose"
fi

# 若从新包目录执行升级，同步最新 scripts 到安装目录（f2cctl/服务脚本依赖它）
if [[ "$FIT2CLOUD_DIR" != "$WORK_DIR" && -d "$FIT2CLOUD_DIR/scripts" && -d "$WORK_DIR/scripts" ]]; then
    cp -rf "$FIT2CLOUD_DIR/scripts/." "$WORK_DIR/scripts/"
fi

log_info "更新运维工具..."
cp -f "$SCRIPT_DIR/fit2cloud.service" /etc/init.d/fit2cloud 2>/dev/null || true
chmod a+x /etc/init.d/fit2cloud 2>/dev/null || true

# f2cctl 以 shim 方式部署（f2cctl 按自身位置解析安装目录，直接拷到 /usr/bin 会解析成 /scripts）
if [[ -f "$SCRIPT_DIR/f2cctl" ]]; then
    if [[ -d "$WORK_DIR/bin/fit2cloud/standalone" ]]; then
        cp -f "$SCRIPT_DIR/f2cctl" "$WORK_DIR/bin/fit2cloud/standalone/f2cctl"
        chmod +x "$WORK_DIR/bin/fit2cloud/standalone/f2cctl"
    fi
    chmod +x "$SCRIPT_DIR/f2cctl"
    cat > /usr/bin/f2cctl <<EOF
#!/bin/bash
# Fit2Cloud 2.0 管理命令（upgrade.sh 生成）
exec $SCRIPT_DIR/f2cctl "\$@"
EOF
    chmod +x /usr/bin/f2cctl
    log_info "已更新管理命令: /usr/bin/f2cctl → $SCRIPT_DIR/f2cctl"
fi

unit_src="$SCRIPT_DIR/fit2cloud.systemd"
if [[ -f "$unit_src" ]]; then
    unit_file="/etc/systemd/system/fit2cloud.service"
    cp -f "$unit_src" "$unit_file"
    sed -i -E "s|/opt/fit2cloud|${INSTALLER_PATH}/fit2cloud|g" "$unit_file"
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

log_info "加载 Docker 镜像..."
images_dir="$FIT2CLOUD_DIR/docker-images"
if [[ -d "$images_dir" ]]; then
    total=$(ls "$images_dir"/*.tar 2>/dev/null | wc -l)
    current=0
    for tar_file in "$images_dir"/*.tar; do
        [[ ! -f "$tar_file" ]] && continue
        current=$((current + 1))
        log_info_inline "[$current/$total] $(basename "$tar_file")"
        docker load -qi "$tar_file"
        log_ok
    done

    # 镜像对账：compose 期望的镜像必须全部就绪
    local_missing=0
    for img in $(get_all_images "$ENV_FILE"); do
        if ! docker image inspect "$img" >/dev/null 2>&1; then
            log_error "镜像缺失: $img"
            local_missing=$((local_missing + 1))
        fi
    done
    if [[ $local_missing -gt 0 ]]; then
        log_error "共缺失 $local_missing 个镜像，升级包可能不完整"
        exit 1
    fi
    log_success "镜像对账通过"
fi

log_info "清理旧版本镜像..."
if [[ -f "$WORK_DIR/conf/version" ]]; then
    old_version=$(cat "$WORK_DIR/conf/version" 2>/dev/null | awk '{print $1}')
    if [[ -n "$old_version" ]]; then
        docker images --format '{{.Repository}}:{{.Tag}}' | grep "$old_version" | xargs -r docker rmi -f 2>/dev/null || true
    fi
fi

log_info "更新版本号..."
if [[ -f "$FIT2CLOUD_DIR/conf/version" ]]; then
    cp -f "$FIT2CLOUD_DIR/conf/version" "$WORK_DIR/conf/version"
fi

log_info "合并配置文件..."
# 若安装目录采用变量分层（install.env / runtime.env），重新合并生成运行期契约 .env
# 两个 example 排在用户文件之前兜底：新版本新增的变量默认值自动补入，用户修改保留
if [[ -f "$WORK_DIR/install.env" || -f "$WORK_DIR/runtime.env" ]]; then
    merge_env_files "$WORK_DIR/.env" "$FIT2CLOUD_DIR/.env" \
        "$FIT2CLOUD_DIR/runtime.env.example" "$FIT2CLOUD_DIR/install.env.example" \
        "$WORK_DIR/runtime.env" "$WORK_DIR/install.env"
    log_info ".env 已重新合并 (runtime.env + install.env)"
fi

log_info "重新渲染配置文件..."
if [[ -f "$FIT2CLOUD_DIR/conf/fit2cloud.properties.tpl" ]]; then
    do_render "$ENV_FILE" "$FIT2CLOUD_DIR/conf" "$WORK_DIR/conf"
fi

log_info "启动 FIT2CLOUD 服务..."
service_up "$WORK_DIR" "$ENV_FILE"

rm -f "$PROGRESS_FILE" "$OLD_COMPOSE_DIR.bak" 2>/dev/null || true

log_success "FIT2CLOUD 升级完成"
