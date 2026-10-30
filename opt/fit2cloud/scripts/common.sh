#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

# =============================================================================
# Fit2Cloud 2.0 通用工具函数库
# =============================================================================

# 颜色定义
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# =============================================================================
# 日志输出函数
# =============================================================================

get_padding() {
    export LC_ALL=en_US.UTF-8
    local msg=$1
    local total_width=70
    len1=$(echo "$msg" | grep -o '[^一-龥]' | wc -l)
    len2=$(echo "$msg" | grep -o "[一-龥]" | wc -l)
    length=$(( len1 + len2 * 2 ))
    printf -v padding '%*s' $(( total_width - length )) ''
}

log_info_inline() {
    local msg="$1"
    get_padding "$msg"
    echo -ne "${GREEN}[INFO] ${NC} $1 $padding"
}

log_info() {
    echo -e "${GREEN}[INFO] ${NC}$1"
}

log_step_warn() {
    echo -e "${YELLOW}$1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] ${NC} $1"
}

log_step_error() {
    echo -e "${RED}$1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] ${NC} $1" >&2
}

log_ok() {
    echo -e "${CYAN}OK${NC} ${1:-}"
}

log_step_success() {
    echo -e "${CYAN}$1${NC} "
}

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

print_title() {
    echo -e "\n\n${CYAN}******************************\t $1 \t******************************${NC}\n"
}

print_subtitle() {
    echo -e "\n${BLUE}------------------\t $1 \t------------------${NC}\n"
}

# =============================================================================
# 环境变量处理函数
# =============================================================================

get_env_value() {
    local key="$1"
    local default_value="$2"
    local env_file="$3"

    if [[ -z "$env_file" || ! -f "$env_file" ]]; then
        echo "$default_value"
        return
    fi

    local value
    value=$(grep -E "^$key=" "$env_file" 2>/dev/null | grep -v '^#' | head -n 1 | cut -d'=' -f2-)

    if [[ -n "$value" ]]; then
      echo "$value"
    else
      echo "$default_value"
    fi
}

set_env_value() {
    local key="$1"
    local new_value="$2"
    local env_file="$3"

    if [[ -z "$env_file" ]]; then
        log_error "set_env_value: 未指定 env_file"
        return 1
    fi

    # 用 awk 重写而非 sed -i：GNU/BSD sed 的 -i 行为不一致，且值可能含 & / \ 等特殊字符
    if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
        CE_SEV_KEY="$key" CE_SEV_VAL="$new_value" awk '
            $0 ~ "^" ENVIRON["CE_SEV_KEY"] "=" {
                if (!done) { print ENVIRON["CE_SEV_KEY"] "=" ENVIRON["CE_SEV_VAL"]; done = 1 }
                next
            }
            { print }
            END { if (!done) print ENVIRON["CE_SEV_KEY"] "=" ENVIRON["CE_SEV_VAL"] }
        ' "$env_file" > "${env_file}.tmp.$$" && mv "${env_file}.tmp.$$" "$env_file"
    else
        echo "${key}=${new_value}" >> "$env_file"
    fi
}

# 合并多个 env 文件为单个输出文件：键唯一化，同名键以后面的文件为准（后文件覆盖前文件）。
# 用途：安装时把 runtime.env（运行变量）+ install.env（安装变量）+ .env（打包变量）
# 合并生成 <安装目录>/fit2cloud/.env —— 运行期唯一契约，f2cctl/compose/重渲染只读它。
merge_env_files() {
    local out_file="$1"
    shift

    local merged
    merged=$(awk '
        /^[A-Za-z_][A-Za-z0-9_]*=/ {
            key = $0; sub(/=.*/, "", key)
            if (!(key in seen)) { seen[key] = 1; order[++n] = key }
            value[key] = $0
        }
        END { for (i = 1; i <= n; i++) print value[order[i]] }
    ' "$@" 2>/dev/null)

    {
        echo "# 本文件由安装脚本自动生成（runtime.env + install.env + 打包 .env 合并）"
        echo "# 如需修改配置，请编辑 install.env / runtime.env 后重新安装或升级"
        echo "# 手动改动会在下次安装/升级时被覆盖"
        [[ -n "$merged" ]] && { echo ""; echo "$merged"; }
    } > "$out_file"
}

# =============================================================================
# 中间件通用函数
# =============================================================================

mw_init() {
    local caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    MW_SCRIPT_DIR="$(cd "$(dirname "$caller")" && pwd)"
    MW_BASE_DIR="$(cd "$MW_SCRIPT_DIR/.." && pwd)"
    ENV_FILE="$MW_BASE_DIR/../.env"
}

mw_is_external() {
    local external_key="$1"
    local external=$(get_env_value "$external_key" "false" "$ENV_FILE")
    [[ "$external" == "true" ]]
}

mw_check_external() {
    local name="$1"
    local external_key="$2"
    local host="$3"
    local port="$4"

    if mw_is_external "$external_key"; then
        log_info "$name: 外部 ($host:$port)"
        return 0
    else
        log_info "$name: 内置"
        return 1
    fi
}

mw_check_url() {
    local url="$1"
    curl -sf "$url" &>/dev/null
}

mw_skip_install() {
    local name="$1"
    local external_key="$2"

    if mw_is_external "$external_key"; then
        log_info "$name: 使用外部，跳过安装"
        return 0
    fi
    log_info "$name: 由 Docker Compose 管理，无需单独安装"
}

mw_skip_configure() {
    local name="$1"
    local external_key="$2"

    if mw_is_external "$external_key"; then
        return 0
    fi
}

mw_set_permissions() {
    local name="$1"
    local path="$2"

    if [[ -f "$path" ]]; then
        chmod 600 "$path"
        log_info "$name 配置权限已设为 600"
    elif [[ -d "$path" ]]; then
        find "$path" -maxdepth 1 -exec chmod 600 {} + 2>/dev/null || true
        log_info "$name 配置权限已设为 600"
    fi
}

# =============================================================================
# 通用函数
# =============================================================================

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

get_local_ip() {
    ip route get 1 2>/dev/null | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p'
}

ensure_dir() {
    local dir_path=$1
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
        log_info "创建目录: $dir_path"
    fi
}

safe_execute() {
    local msg="$1"
    shift

    log_info_inline "$msg..."
    if ! "$@" >>"${INSTALL_LOG:-/dev/null}" 2>&1; then
        log_step_error "执行失败"
        return 1
    fi
    log_ok
    return 0
}

download_file() {
    local url="$1"
    local output="$2"

    if cmd_exists curl; then
        curl -L --progress-bar -f -o "$output" "$url"
    elif cmd_exists wget; then
        wget -q --show-progress -O "$output" "$url"
    else
        log_error "wget 和 curl 都未安装"
        return 1
    fi
}

# =============================================================================
# 文件操作函数
# =============================================================================

calculate_md5() {
    local file=$1
    local md5_file="${file}.md5"

    if [[ -f "$file" ]]; then
        md5sum "$file" > "$md5_file"
        log_info "MD5 计算完成: $md5_file"
        echo "$md5_file"
    else
        log_error "文件不存在: $file"
        return 1
    fi
}

# =============================================================================
# 端口检测函数
# =============================================================================

check_port() {
    local port=$1

    if [[ -z "$port" ]]; then
        return 0
    fi

    log_info_inline "检查端口 $port 占用..."

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_step_error "必须为数字"
        return 1
    fi

    local record=0
    if cmd_exists lsof; then
        record=$(lsof -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | wc -l)
    elif cmd_exists netstat; then
        record=$(netstat -tnl 2>/dev/null | awk '{print $4}' | grep -cE "[:.]$port$") || true
    elif cmd_exists ss; then
        record=$(ss -tnl 2>/dev/null | awk '{print $4}' | grep -cE "[:.]$port$") || true
    else
        log_step_warn "未找到检测工具 (lsof/netstat/ss)，跳过端口检测"
        return 0
    fi

    if [[ "$record" -eq "0" ]]; then
        log_ok
        return 0
    else
        log_step_error "已占用"
        return 1
    fi
}

# =============================================================================
# 系统检测函数
# =============================================================================

get_os() {
    local os="unknown"

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu)       os="ubuntu" ;;
            openEuler)    os="openEuler" ;;
            kylin)        os="kylin" ;;
            centos|rhel|rocky|alma) os="$ID" ;;
            *)            os="$ID" ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        os="redhat"
    fi

    echo "$os"
}

get_os_version() {
    local os=$(get_os)
    local major_version="unknown"

    if [[ -f /etc/redhat-release ]] && [[ "$os" =~ ^(centos|rhel|rocky|alma|redhat)$ ]]; then
        major_version=$(awk '{print $3}' /etc/redhat-release | cut -d. -f1)
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        major_version=$(echo "$VERSION_ID" | cut -d. -f1)
    fi

    echo "$major_version"
}

read_with_default() {
    local prompt="$1"
    local default="$2"
    local input

    if [[ "${SILENT_MODE:-false}" == "true" ]]; then
        echo "$prompt [$default]: " >&2
        echo "$default"
        return
    fi
    read -r -p "$prompt [$default]: " input
    echo "${input:-$default}"
}
