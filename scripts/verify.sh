#!/bin/bash
# =============================================================================
# 一键校验脚本：打包/安装脚本的静态检查 + 渲染冒烟测试
#
# 用法: bash scripts/verify.sh
#   全部通过退出码 0；任何一步失败立即报错退出。
# 建议在提交前和 Jenkins 打包前各跑一次。
# =============================================================================
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

step() {
    echo ""
    echo "==> $1"
}

# -----------------------------------------------------------------------------
# 1. bash -n：所有 shell 脚本语法检查
# -----------------------------------------------------------------------------
step "1/4 bash 语法检查 (bash -n)"
while IFS= read -r f; do
    if ! bash -n "$f" 2>&1; then
        echo "FAIL: $f"
        FAIL=1
    fi
done < <(find "$BASE_DIR" -name "*.sh" -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/dist/*")
echo "bash -n 完成"

# -----------------------------------------------------------------------------
# 2. shellcheck：静态分析（未安装时跳过并提示）
# -----------------------------------------------------------------------------
step "2/4 shellcheck 静态分析"
if command -v shellcheck >/dev/null 2>&1; then
    # 全局豁免（均有明确理由，新增豁免需在此说明）：
    #   SC1090/SC1091 source 路径为运行期变量，无法静态解析
    #   SC2155 项目约定 local x=$(get_env_value ...) 自带默认值、有意容错（112 处，改写风险大于收益）
    #   SC2012  ls|wc -l 仅用于计数，文件名不受控场景不存在
    #   SC2086  $profile_args/$env_args/$mw_list 等标志与列表字符串有意按空白展开（已人工逐一审阅）
    #   SC2129/SC2181 纯风格类（多行重定向、$? 判空），不强制
    while IFS= read -r f; do
        if ! shellcheck -e SC1090,SC1091,SC2155,SC2012,SC2086,SC2129,SC2181 "$f" 2>&1; then
            FAIL=1
        fi
    done < <(find "$BASE_DIR/opt/fit2cloud/scripts" "$BASE_DIR/scripts" \
                 "$BASE_DIR/opt/fit2cloud/bin" "$BASE_DIR/opt/fit2cloud/tools" \
                 -name "*.sh" -not -path "*/.git/*" 2>/dev/null)
    echo "shellcheck 完成"
else
    echo "shellcheck 未安装，跳过 (建议: brew install shellcheck / apt install shellcheck)"
fi

# -----------------------------------------------------------------------------
# 3. Go：render-cfg 编译 + vet
# -----------------------------------------------------------------------------
step "3/4 render-cfg 编译检查"
if command -v go >/dev/null 2>&1; then
    (cd "$BASE_DIR/render-cfg" && go vet ./... && go build -o /tmp/ce-render-cfg-verify .)
    echo "go vet + build 完成"
else
    echo "go 未安装，跳过"
    test -x "$BASE_DIR/opt/fit2cloud/bin/fit2cloud/standalone/ce-render-cfg-amd64" \
        || { echo "FAIL: 无 go 且无预编译 render-cfg 二进制"; FAIL=1; }
fi

# -----------------------------------------------------------------------------
# 4. 渲染冒烟测试：用示例配置实际渲染一遍 conf，校验关键输出
# -----------------------------------------------------------------------------
step "4/4 配置渲染冒烟测试"
RENDER_BIN=/tmp/ce-render-cfg-verify
if [[ ! -x "$RENDER_BIN" ]]; then
    RENDER_BIN=$(ls "$BASE_DIR"/render-cfg/bin/ce-render-cfg-* 2>/dev/null | head -1 || true)
fi
if [[ -n "$RENDER_BIN" && -x "$RENDER_BIN" ]]; then
    TMP_OUT=$(mktemp -d)
    TMP_ENV=$(mktemp)
    # 以两个示例配置为输入（install.env 覆盖 runtime.env），补齐必填的访问 IP
    cp "$BASE_DIR/opt/fit2cloud/install.env.example" "$TMP_ENV"
    echo "CE_ACCESS_IP=127.0.0.1" >> "$TMP_ENV"
    export CE_ENCRYPTION_KEY="${CE_ENCRYPTION_KEY:-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef}"
    if "$RENDER_BIN" -t "$BASE_DIR/opt/fit2cloud/conf" -o "$TMP_OUT" \
        -e "$BASE_DIR/opt/fit2cloud/runtime.env.example" -e "$TMP_ENV" >/dev/null; then
        if grep -q "^fit2cloud.cmp.address=http://127.0.0.1$" "$TMP_OUT/fit2cloud.properties" \
            && grep -q "^rdb.password=" "$TMP_OUT/fit2cloud.properties" \
            && grep -q '^  id = "{{ .Group }}' "$TMP_OUT/telegraf/kapacitor.conf"; then
            echo "渲染冒烟测试通过 → $TMP_OUT"
        else
            echo "FAIL: 渲染输出缺少关键配置项"
            head -5 "$TMP_OUT/fit2cloud.properties"
            FAIL=1
        fi
    else
        echo "FAIL: 渲染失败"
        FAIL=1
    fi
else
    echo "无可用 render-cfg 二进制，跳过"
fi

echo ""
if [[ "$FAIL" == "0" ]]; then
    echo "✅ 全部校验通过"
else
    echo "❌ 校验失败，请修复上方 FAIL 项"
    exit 1
fi
