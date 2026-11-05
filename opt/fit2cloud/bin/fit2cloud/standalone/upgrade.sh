#!/bin/bash
# Fit2Cloud 升级脚本（f2cctl upgrade <升级包> 解压后调用，也可在解压目录内直接执行）
# 用法: upgrade.sh [--skip-backup]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIT2CLOUD_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$FIT2CLOUD_DIR/scripts/common.sh"
source "$FIT2CLOUD_DIR/scripts/docker.sh"
source "$FIT2CLOUD_DIR/scripts/service.sh"
source "$FIT2CLOUD_DIR/scripts/render.sh"

ENV_FILE="$FIT2CLOUD_DIR/.env"
INSTALLER_PATH=$(get_env_value CE_INSTALL_PATH "/opt" "$ENV_FILE")
WORK_DIR="$INSTALLER_PATH/fit2cloud"

OLD_COMPOSE_DIR="$WORK_DIR/external-compose"
NEW_COMPOSE_DIR="$FIT2CLOUD_DIR/external-compose"
COMPOSE_BACKUP_DIR="$OLD_COMPOSE_DIR.bak"

# 已完成步骤（回滚时逆序执行）
COMPLETED_STEPS=()
PROGRESS_FILE="$WORK_DIR/.upgrade-progress"
SKIP_BACKUP=false

show_usage() {
    cat << 'EOF'
用法: upgrade.sh [--skip-backup]

  --skip-backup   跳过升级前的 conf/data/compose 备份（data 目录大时可显著提速，失败不可自动回退）
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-backup)  SKIP_BACKUP=true; shift ;;
        -h|--help)      show_usage; exit 0 ;;
        *)              die "未知参数: $1 (--help 查看用法)" ;;
    esac
done

[[ -d "$WORK_DIR" ]] || die "安装目录不存在: $WORK_DIR（请确认 CE_INSTALL_PATH 与已完成安装）"

rollback() {
    log_error "升级失败，按已完成步骤逆序回滚..."
    local i
    for (( i = ${#COMPLETED_STEPS[@]} - 1; i >= 0; i-- )); do
        case "${COMPLETED_STEPS[$i]}" in
            update_compose)
                log_info "回滚: 恢复原 compose 编排"
                mkdir -p "$OLD_COMPOSE_DIR"
                cp -rf "$COMPOSE_BACKUP_DIR/." "$OLD_COMPOSE_DIR/" 2>/dev/null || true ;;
            service_down)
                log_info "回滚: 启动原有服务"
                service_up "$WORK_DIR" "$ENV_FILE" 2>/dev/null || true ;;
        esac
    done
    log_error "回滚完成，请检查错误后重试（升级前备份保留在 $WORK_DIR/backup 下）"
    exit 1
}

trap rollback ERR

mark_step_done() {
    local step="$1"
    echo "$step" >> "$PROGRESS_FILE"
    COMPLETED_STEPS+=("$step")
}

do_pre_upgrade_backup() {
    local backup_time
    backup_time=$(date "+%Y-%m-%d-%H-%M-%S")
    local backup_dir="$WORK_DIR/backup/pre-upgrade-$backup_time"
    ensure_dir "$backup_dir"

    log_info "备份 conf / data / compose / env → $backup_dir (data 目录大时耗时较长)"
    cp -rp "$WORK_DIR/conf" "$backup_dir/"
    if [[ -d "$WORK_DIR/data" ]]; then
        cp -rp "$WORK_DIR/data" "$backup_dir/"
    fi
    if [[ -d "$OLD_COMPOSE_DIR" ]]; then
        cp -rp "$OLD_COMPOSE_DIR" "$backup_dir/"
    fi

    local f
    for f in .env install.env runtime.env; do
        [[ -f "$WORK_DIR/$f" ]] && cp -p "$WORK_DIR/$f" "$backup_dir/"
    done

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

log_info "更新 compose 编排..."
if [[ -d "$NEW_COMPOSE_DIR" ]]; then
    rm -rf "$COMPOSE_BACKUP_DIR"
    if [[ -d "$OLD_COMPOSE_DIR" ]]; then
        cp -rf "$OLD_COMPOSE_DIR" "$COMPOSE_BACKUP_DIR"
    fi
    mkdir -p "$OLD_COMPOSE_DIR"
    cp -rf "$NEW_COMPOSE_DIR/." "$OLD_COMPOSE_DIR/"
    mark_step_done "update_compose"
fi

# 同步最新脚本与运维工具到安装目录（f2cctl / init.d 脚本依赖 scripts 库；
# 旧版本安装目录可能缺 scripts，这里无条件补齐）
if [[ "$FIT2CLOUD_DIR" != "$WORK_DIR" && -d "$FIT2CLOUD_DIR/scripts" ]]; then
    ensure_dir "$WORK_DIR/scripts"
    cp -rf "$FIT2CLOUD_DIR/scripts/." "$WORK_DIR/scripts/"
fi

log_info "更新运维工具..."
if [[ -f "$SCRIPT_DIR/fit2cloud.service" ]] && command -v service >/dev/null 2>&1; then
    if cp -f "$SCRIPT_DIR/fit2cloud.service" /etc/init.d/fit2cloud; then
        chmod a+x /etc/init.d/fit2cloud
        service fit2cloud chkconfig --add fit2cloud >/dev/null 2>&1 || true
        service fit2cloud chkconfig fit2cloud on >/dev/null 2>&1 || true
    else
        log_warn "未写入 /etc/init.d/fit2cloud（无权限或系统不支持）"
    fi
fi

# f2cctl 以 shim 方式部署（f2cctl 按自身位置解析安装目录，直接拷到 /usr/bin 会解析成 /scripts）
if [[ -f "$SCRIPT_DIR/f2cctl" ]]; then
    if [[ -d "$WORK_DIR/bin/fit2cloud/standalone" ]]; then
        cp -f "$SCRIPT_DIR/f2cctl" "$WORK_DIR/bin/fit2cloud/standalone/f2cctl"
        chmod +x "$WORK_DIR/bin/fit2cloud/standalone/f2cctl"
    fi
    chmod +x "$SCRIPT_DIR/f2cctl"
    cat > /usr/bin/f2cctl << EOF
#!/bin/bash
# Fit2Cloud 2.0 管理命令（upgrade.sh 生成）
exec "$SCRIPT_DIR/f2cctl" "\$@"
EOF
    chmod +x /usr/bin/f2cctl
    log_info "已更新管理命令: /usr/bin/f2cctl → $SCRIPT_DIR/f2cctl"
fi

unit_src="$SCRIPT_DIR/fit2cloud.systemd"
if [[ -f "$unit_src" && -d /etc/systemd/system ]]; then
    local_unit="/etc/systemd/system/fit2cloud.service"
    cp -f "$unit_src" "$local_unit"
    replace_in_file "$local_unit" "s|/opt/fit2cloud|$(escape_sed_replacement "$INSTALLER_PATH")/fit2cloud|g"
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

log_info "加载 Docker 镜像..."
images_dir="$FIT2CLOUD_DIR/docker-images"
if [[ -d "$images_dir" ]]; then
    total=$(ls "$images_dir"/*.tar 2>/dev/null | wc -l || true)
    current=0
    for tar_file in "$images_dir"/*.tar; do
        [[ -f "$tar_file" ]] || continue
        current=$((current + 1))
        log_info_inline "[$current/$total] $(basename "$tar_file")"
        docker load -qi "$tar_file"
        log_ok
    done

    # 镜像对账：compose 期望的镜像必须全部就绪
    missing=0
    # 镜像名不含空白，按空白展开是有意的
    # shellcheck disable=SC2046
    for img in $(get_all_images "$ENV_FILE"); do
        if ! docker image inspect "$img" >/dev/null 2>&1; then
            log_error "镜像缺失: $img"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -gt 0 ]]; then
        die "共缺失 $missing 个镜像，升级包可能不完整"
    fi
    log_success "镜像对账通过"
fi

log_info "清理旧版本镜像..."
if [[ -f "$WORK_DIR/conf/version" ]]; then
    old_version=$(head -1 "$WORK_DIR/conf/version" 2>/dev/null || true)
    if [[ -n "$old_version" ]]; then
        old_image=""
        while IFS= read -r old_image; do
            [[ -n "$old_image" ]] && docker rmi -f "$old_image" >/dev/null 2>&1 || true
        done < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -F "$old_version" || true)
    fi
fi

log_info "更新版本号..."
if [[ -f "$FIT2CLOUD_DIR/conf/version" ]]; then
    cp -f "$FIT2CLOUD_DIR/conf/version" "$WORK_DIR/conf/version"
fi

log_info "合并配置文件..."
# 安装目录采用变量分层（install.env / runtime.env）时重新合并运行期契约 .env
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

rm -f "$PROGRESS_FILE"
rm -rf "$COMPOSE_BACKUP_DIR"

log_success "FIT2CLOUD 升级完成，可用 f2cctl health 检查服务状态"
