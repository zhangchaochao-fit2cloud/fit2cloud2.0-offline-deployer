# Shell 脚本规范（STYLE.md）

> 适用范围：`package.sh`、`scripts/package/*.sh`、`scripts/verify.sh`、`opt/fit2cloud/scripts/**`、
> `opt/fit2cloud/bin/fit2cloud/standalone/**`、`opt/install.sh`
> 规范依据：Google Shell Style Guide、ShellCheck wiki，结合本项目实际（CentOS 7 bash 4.2、Jenkins CI、被 source 的库结构）裁剪。
> 门禁：`bash scripts/verify.sh`（bash -n → shellcheck → go vet/build → 渲染冒烟），提交/打包前必跑。

## 1. 文件与分层

| 层 | 位置 | 规则 |
|---|---|---|
| 入口脚本 | `package.sh`、`opt/install.sh`、`opt/fit2cloud/scripts/install.sh`、`standalone/*.sh` | 必须 `set -euo pipefail`；shebang `#!/bin/bash` |
| 打包子脚本 | `scripts/package/*.sh` | `set -euo pipefail`；只定义函数，由 package.sh source 后调用 |
| 库文件 | `opt/fit2cloud/scripts/*.sh`、`middleware/*.sh` | 不加 set（由入口提供）；文件头带"库文件"注释；**必须带 source 守卫**（见 §2） |

- 目录职责：打包流水线 `scripts/package/`（prepare → pull-images → export-images → download-tools → create-package）；
  安装/运行期库 `opt/fit2cloud/scripts/`；两者共用 `common.sh`（日志/env 工具/下载）。
- 库文件不做入口参数解析；入口不写业务细节。

## 2. source 守卫（include-once）

含 `readonly` 常量或被多处 source 的库文件，文件头必须加守卫：

```bash
[[ -n "${_F2C_COMMON_SOURCED:-}" ]] && return 0
# ... 文件末尾或常量区：
readonly _F2C_COMMON_SOURCED=1
```

原因：`common.sh`/`docker.sh` 存在双重 source（入口直接 source + 彼此嵌套 source），
readonly 常量二次声明会直接报错终止。守卫变量命名：`_F2C_<模块>_SOURCED`。

## 3. 命名

- 函数：snake_case 动词开头（`check_docker`、`copy_plugins`）；模块内部函数加 `_` 前缀（`_export_one`、`_run_compose`）。
- **禁止函数嵌套定义**（函数体内再定义函数）：每次调用都会重定义，提升为文件级 `_xxx`。
- 常量：全大写 + `readonly`（颜色、`*_DEFAULT` 默认值、哨兵变量）。
- 全局可变变量：全大写无 readonly；函数内一律 `local`。
- 跨文件全局变量（被 source 链下游消费）：赋值处加标注，见 §5。

## 4. 错误处理

- `set -euo pipefail` 只在入口；库内依赖入口的严格模式，**勿在库文件单独 set**。
- `|| true` 分级原则（2026-10-27 基线，已清理 9 处违规）：
  - **允许**：清理/幂等/回滚路径（`rm`、目录创建、`daemon-reload`、回滚分支、`wait`）
  - **禁止**：产生真实结果的命令（`cp`/`rpm`/`unzip`/`wget`/`tar`）——失败必须暴露
- 命令替换必须处理失败语义：
  - 有意容错取默认值：`local x=$(get_env_value K def "$FILE")`（项目约定，已豁免 SC2155）
  - 需要感知失败：先声明后赋值（`local x; x=$(cmd)`），失败交给 set -e
- 长耗时/可挂死的外部命令必须 `timeout` 兜底（如 `DOCKER_SAVE_TIMEOUT`）。
- 原子写：先写 `<file>.part`，成功后 `mv` 改名；命中类校验必须同时校验配套 sidecar（如 `.md5`）。

## 5. shellcheck 豁免清单（集中在 scripts/verify.sh，新增必须写理由）

| 规则 | 理由 |
|---|---|
| SC1090/SC1091 | source 路径为运行期变量，无法静态解析 |
| SC2155 | `local x=$(get_env_value ...)` 自带默认值、有意容错（110+ 处，改写风险大于收益）|
| SC2086 | `$profile_args`/`$env_args`/镜像列表等**有意按空白展开**（已人工逐一审阅；镜像名不含空格）|
| SC2012 | ls\|wc -l 仅计数，不存在文件名受控问题 |
| SC2129/SC2181 | 纯风格（多行重定向、$? 判空），不强制 |

跨文件全局变量（单文件视角的 SC2034 误报）**不走集中豁免**，在赋值行前加行内标注：

```bash
# shellcheck disable=SC2034  # 消费方：render.sh / service.sh
IMAGE_ADDRESS=$(get_env_value IMAGE_ADDRESS "registry.fit2cloud.com/north" "$INSTALL_ENV")
```

## 6. 日志（common.sh 统一函数，调用侧禁止自行 echo -e/printf 格式化）

| 函数 | 输出格式 |
|---|---|
| `log_info` / `log_warn` / `log_error` / `log_success` | `[HH:MM:SS] [级别] 消息`（时间戳在级别前）|
| `log_info_inline` + `log_ok` | 同前缀 + padding 对齐 + 行尾 `OK`（仅顺序执行的短步骤用）|
| `print_title` | `========== 1/5 步骤名 ==========`（编号 N/5）|
| `print_subtitle` | `── 子动作` |

- 时间戳函数 `log_timestamp`；颜色常量 RED/GREEN/YELLOW/BLUE/CYAN/NC（readonly）。
- 格式化输出一律 `printf '%b\n'`（不要新增 `echo -e`）。
- 并发子进程内**不要直接打日志**（会交错），结果写临时文件、主进程汇总后输出（参考 pull-images.sh / docker.sh 导出）。
- 长耗时步骤的原始输出收敛到 `dist/*.log`，失败时提示日志位置（参考 render-cfg 编译）。

## 7. 可移植性

- 部署目标为 Linux（CentOS 7+），但开发机可能是 macOS：禁用 GNU 专属选项
  （`sed -i` 后缀差异 → `set_env_value` 用 awk 重写；`stat`/`date -d` 差异敏感处避免使用）。
- bash 4.2 基线：不用关联数组（如需按名分组计数用 awk）。
- 下载统一走 `download_file`（curl 优先、wget 兜底、重试 + 断点续传），**禁止各处直接调 wget/curl**；
  CI（无 TTY）自动静默，TTY 才显示进度。

## 8. 路径与时序约定（勿破坏）

- `bin/` 保持 `opt/fit2cloud/bin/fit2cloud/standalone/` 原位，standalone 内脚本靠 `SCRIPT_DIR/../../..` 定位；
  CLI 部署用固定路径 shim（install.sh 的 deploy_cli_tools 已实现），**不得直接拷脚本到 /usr/bin**。
- `CE_ACCESS_IP` 自动探测、MinIO/中间件运行期密钥必须在渲染（do_render_config）之前完成——渲染后写 .env 不会反映到 conf。
- 中间件镜像的平台 tag 映射集中在 package.sh `middleware_image()`；新增"独立 arm64 tag"的镜像在此登记，
  compose 侧引用 `<NAME>_DOCKER_IMAGE` 变量。

## 9. 典型反模式（审查即拒绝）

```bash
# ✗ 函数内嵌套定义
outer() { inner() { ...; }; inner; }

# ✗ ls | grep 解析文件名（SC2010）
legacy=$(ls -t "$dir"/*.tar | grep -vE 'pattern')

# ✗ 绕过日志函数直接格式化输出
echo -e "${GREEN}标题${NC}"

# ✗ 非清理路径吞错
cp a b || true

# ✗ 无超时的可挂死命令
docker save "${images[@]}"
```
