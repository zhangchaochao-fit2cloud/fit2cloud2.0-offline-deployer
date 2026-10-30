# Fit2Cloud 2.0 Offline Deployer

Fit2Cloud 2.0 离线部署工具 — 支持打包、安装、升级、扩展的一体化离线部署方案。

## 目录结构

```
fit2cloud2.0-offline-deployer/
├── package.sh                          # 打包入口脚本
├── packaging.env.example               # 打包时环境变量模板
├── scripts/package/                    # 打包分步脚本
│   ├── prepare.sh                      #   准备安装文件
│   ├── pull-images.sh                  #   拉取 Docker 镜像
│   ├── export-images.sh                #   导出 Docker 镜像
│   ├── download-tools.sh               #   下载工具包
│   └── create-package.sh               #   创建安装包
├── render-cfg/                         # Go 模板渲染引擎
│   ├── main.go
│   ├── Makefile
│   └── render/
│       ├── crypto.go                   #   AES-GCM 加解密
│       ├── template.go                 #   Go 模板函数
│       └── version.go
└── opt/fit2cloud/                      # 安装包内容
    ├── .env                            #   打包写入的变量（IMAGE_ADDRESS/VERSION/PLATFORM）
    ├── install.env.example             #   安装期变量模板（模式/路径/集群/组件开关）
    ├── runtime.env.example             #   运行期变量模板（中间件/密码/Nginx/性能）
    ├── conf/                           #   配置模板（.tpl 渲染后生成实际文件）
    │   ├── fit2cloud.properties.tpl    #   Go 模板主配置
    │   ├── mysql/mysql.env.tpl         #   MySQL 密码模板
    │   ├── redis/redis.env.tpl         #   Redis 密码模板
    │   ├── redis/redis.conf.tpl        #   Redis 配置模板
    │   ├── minio/minio.env.tpl         #   MinIO 密码模板
    │   ├── keycloak/keycloak.properties.tpl
    │   ├── telegraf/telegraf.conf.tpl  #   Telegraf 配置模板
    │   ├── telegraf/kapacitor.conf.tpl #   Kapacitor 配置模板
    │   └── ...
    ├── external-compose/               #   Docker Compose 编排
    │   ├── base-docker-compose.yml     #   基础服务（9 个微服务）
    │   ├── ha-docker-compose.yml       #   集群模式覆盖（CE_MODE=cluster 时加载）
    │   └── middleware/                 #   中间件 compose 文件（按需加载）
    │       ├── mysql-docker-compose.yml
    │       ├── redis-docker-compose.yml
    │       ├── influxdb-docker-compose.yml
    │       ├── rabbitmq-docker-compose.yml
    │       ├── minio-docker-compose.yml
    │       ├── keycloak-docker-compose.yml
    │       ├── ansible-docker-compose.yml
    │       └── websockify-docker-compose.yml
    ├── docker-compose.yml              #   主 compose（extends base + middleware）
    ├── scripts/                        #   安装脚本库
    │   ├── common.sh                   #   通用函数库（mw_init）
    │   ├── docker.sh                   #   Docker 管理
    │   ├── os.sh                       #   系统检查
    │   ├── install.sh                  #   安装主流程（支持断点续装）
    │   ├── render.sh                   #   配置渲染
    │   ├── service.sh                  #   服务生命周期 + 动态 compose 编排
    │   └── middleware/                 #   中间件安装脚本
    │       ├── mysql.sh
    │       ├── redis.sh
    │       ├── influxdb.sh
    │       ├── rabbitmq.sh
    │       ├── minio.sh
    │       ├── keycloak.sh
    │       ├── ansible.sh
    │       ├── nginx.sh
    │       └── telegraf.sh
    ├── bin/fit2cloud/standalone/       #   独立部署工具
    │   ├── install.sh                  #   安装入口（薄包装）
    │   ├── f2cctl                      #   运维控制工具
    │   ├── fit2cloud.service           #   SysV init 服务脚本
    │   ├── fit2cloud.systemd           #   systemd unit 文件
    │   ├── upgrade.sh                  #   升级脚本
    │   ├── fit2cloud-install-extension.sh
    │   └── fit2cloud-upgrade-extension.sh
    └── tools/                          #   工具安装脚本
        ├── minio/minio-install.sh
        └── telegraf/telegraf-install.sh
```

## 打包

### 前置条件

- Docker + docker-compose 或 docker compose V2
- Go 1.18+（编译 ce-render-cfg，可选）
- tar, wget, unzip

### 打包命令

```bash
# 基本打包
./package.sh -v 2.0.1 -b 100

# 完整参数
./package.sh \
  -v 2.0.1 \                     # 版本号
  -b 100 \                       # 构建号
  -r registry.fit2cloud.com/north \  # 镜像仓库
  --platform amd64 \             # 目标平台 (amd64/arm64)
  -o ./dist                      # 输出目录

# 镜像 tag 默认 = <版本号>.<构建号>（勿用 master 等开发标签），可用 -V/--image-version 覆盖
# 打包产物含 fit2cloud/manifest.txt（镜像 md5 清单），安装时自动校验完整性

# 试运行（不实际下载/导出）
./package.sh --dry-run -v 2.0.1

# 跳过 ce-render-cfg 编译
./package.sh --skip-render-cfg -v 2.0.1

# 清理临时文件
./package.sh --clean -v 2.0.1
```

### 打包流程

1. **准备安装文件** — 复制 opt/ 目录、生成 .env、解压 AWS 询价数据
2. **编译 ce-render-cfg** — 交叉编译 amd64/arm64 二进制（需 Go，可用 `--skip-render-cfg` 跳过）
3. **拉取 Docker 镜像** — 根据 compose 文件拉取全部镜像
4. **导出 Docker 镜像** — 保存为 tar 到 docker-images/
5. **下载工具包** — Docker 安装包、MinIO 镜像、Telegraf
6. **创建安装包** — 打包为 `cloudexplorer-<version>-<platform>-<date>.tar.gz`

## 安装

### 系统要求

| 项目 | 最低要求 | 推荐 |
|------|----------|------|
| 操作系统 | CentOS 7+, Ubuntu 20+, openEuler, Kylin | CentOS 7/8 |
| CPU | 4 核 | 8 核 |
| 内存 | 16 GB | 32 GB |
| 磁盘 | 200 GB | 500 GB |
| 架构 | x86_64/amd64, aarch64/arm64 | — |

### 安装步骤

```bash
# 1. 解压安装包
tar zxf cloudexplorer-2.0.1-amd64-2026.07.22.tar.gz

# 2. 进入安装目录
cd installer

# 3. 编辑配置（可选，使用默认值也可）
cp install.env.example install.env    # 安装期变量：模式/路径/集群/组件开关
cp runtime.env.example runtime.env    # 运行期变量：中间件/密码/Nginx/性能
vi install.env runtime.env

# 4. 执行安装
bash install.sh

# 静默安装（无交互）
bash install.sh -s

# 跳过特定组件
bash install.sh --no-minio --no-telegraf --with-nginx

# 指定安装目录
bash install.sh -d /data

# 强制重新安装（忽略断点续装进度）
bash install.sh --force-reinstall
```

### 安装 CLI 参数

| 参数 | 说明 |
|------|------|
| `-s, --silent` | 静默安装，无交互提示 |
| `-d, --dir DIR` | 安装目录（默认 /opt） |
| `-e, --env FILE` | 指定安装期配置文件（默认 install.env） |
| `-r, --runtime-env FILE` | 指定运行期配置文件（默认 runtime.env） |
| `--no-minio` | 跳过 MinIO 安装（使用外部） |
| `--no-telegraf` | 跳过 Telegraf 安装 |
| `--with-nginx` | 安装 Nginx 反向代理 |
| `--force-reinstall` | 忽略已完成的步骤，强制重新安装 |
| `--verify-images` | 全量 md5 校验 Docker 镜像包（默认轻量校验：文件存在性） |
| `-h, --help` | 显示帮助 |

### 配置文件分层（安装变量 / 运行变量分离）

安装变量和运行变量**分开存放，不要混放**：

| 文件 | 阶段 | 内容 | 修改时机 |
|------|------|------|----------|
| `install.env` | 安装期 | 部署模式、安装路径、访问地址、集群拓扑、组件开关（CE_EXTERNAL_*、CE_INSTALL_*） | 安装前；安装完成后一般不动 |
| `runtime.env` | 运行期 | 中间件连接/密码、Nginx、安全、性能、日志、备份 | 随时；改后 `f2cctl upgrade` 重新渲染生效 |
| `.env` | 生成产物 | 安装脚本自动合并（runtime.env + install.env + 打包 .env） | **勿手改**，会被覆盖 |

运行期唯一契约是 `<安装目录>/fit2cloud/.env`：f2cctl、服务管理、docker compose、配置重渲染都只读它。

### 安装配置

**install.env（安装期）：** CE_MODE, CE_INSTALL_PATH, CE_ACCESS_*, CE_CLUSTER_*, CE_PROFILES, CE_EXTERNAL_*, CE_INSTALL_NGINX/TELEGRAF, CE_HEALTHY_TIMEOUT, CE_NETWORK_NAME

**runtime.env（运行期）：

**中间件（外部开关在 install.env）：**
- MySQL: CE_EXTERNAL_MYSQL, CE_MYSQL_HOST/PORT/DB/USER/PASSWORD
- Redis: CE_EXTERNAL_REDIS, CE_REDIS_MODE, CE_REDIS_HOST/PORT/PASSWORD
- InfluxDB: CE_EXTERNAL_INFLUXDB, CE_INFLUXDB_URL/USER/PASSWORD
- RabbitMQ: CE_EXTERNAL_RABBITMQ, CE_RABBITMQ_MODE
- MinIO: CE_EXTERNAL_MINIO, CE_MINIO_ENDPOINT/ACCESS_KEY/SECRET_KEY
- Keycloak: CE_EXTERNAL_KEYCLOAK, CE_KEYCLOAK_PASSWORD, CE_KEYCLOAK_PORT
- Ansible: CE_EXTERNAL_ANSIBLE, CE_ANSIBLE_HOST/PASSWORD

**安全：** CE_ADMIN_USERNAME/PASSWORD, CE_SECURITY_JWT_SECRET, CE_ENCRYPTION_KEY

**性能：** CE_JVM_HEAP_MIN/MAX, CE_MYSQL_POOL_SIZE, CE_REDIS_POOL_SIZE

## 运维管理 (f2cctl)

```bash
# 服务管理
f2cctl start [SERVICE]          # 启动服务
f2cctl stop [SERVICE]           # 停止服务
f2cctl restart [SERVICE]        # 重启服务
f2cctl status                   # 查看状态
f2cctl logs [SERVICE] [LINES]   # 查看日志

# 备份还原
f2cctl backup                   # 全量备份（配置+数据+镜像）
f2cctl restore <FILE>           # 从备份还原
f2cctl backup-image [PATTERN]   # 仅备份 Docker 镜像

# 升级扩展
f2cctl upgrade <FILE>           # 升级
f2cctl install-module <FILE>    # 安装扩展模块
f2cctl import <FILE>            # 导入产品包

# 系统管理
f2cctl repo <ADDRESS>           # 配置 Docker 不安全仓库
f2cctl clean [image|log|all]    # 清理镜像/日志
```

## 模板渲染 (ce-render-cfg)

配置文件使用 Go template 语法渲染，支持以下自定义函数：

| 函数 | 说明 | 示例 |
|------|------|------|
| `default` | 默认值 | `{{ .VAR \| default "fallback" }}` |
| `required` | 必填校验 | `{{ required "VAR is required" .VAR }}` |
| `split` | 字符串分割 | `{{ split .STR "," }}` |
| `toBool` | 转布尔 | `{{ toBool .FLAG }}` |
| `encrypt` | AES-GCM 加密（key 名后缀匹配 --encrypt 列表才加密） | `{{ encrypt "CE_MYSQL_PASSWORD" .CE_MYSQL_PASSWORD }}` |
| `generatePassword` | 生成随机密码 | `{{ generatePassword 16 }}` |

加密密钥通过 `CE_ENCRYPTION_KEY` 环境变量传入（32 字节 base64 编码），生成方式：

```bash
openssl rand -base64 32
```

## 中间件脚本规范

每个中间件脚本位于 `scripts/middleware/<name>.sh`，调用 `mw_init` 初始化，提供 3 个标准函数：

- `check_<name>()` — 检查中间件是否可用
- `install_<name>()` — 安装中间件（幂等）
- `configure_<name>()` — 配置中间件

安装脚本通过 `install_middleware()` 统一调度，根据 `CE_EXTERNAL_*` 环境变量决定跳过内置中间件。

## Compose 动态编排

`service.sh` 的 `get_compose_files()` 动态构建 compose 参数：

1. 始终包含 `base-docker-compose.yml`（或集群模式下 `ha-docker-compose.yml`）
2. 根据 `CE_EXTERNAL_*` 跳过对应中间件的 compose 文件
3. 自动扫描 `$install_dir/extensions/*/docker-compose.yml` 包含扩展模块
4. 自动添加 `--env-file` 参数

所有 compose 文件声明 `cmp-network` 为 `external: true`，由安装脚本预创建。

Docker Compose 命令自动检测：优先使用 `docker compose`（V2），回退到 `docker-compose`（V1）。

## 安全设计

- 密码文件均为 `.tpl` 模板，安装时由 `ce-render-cfg` 渲染生成
- `.gitignore` 排除所有敏感文件（`.env`, `mysql.env`, `minio.env`, `redis.env` 等）
- 完成信息不打印明文密码，引导用户查看 `.env`
- `set_env_value()` 防止 sed 注入攻击

## 开发

### 编译 ce-render-cfg

```bash
cd render-cfg
make cross VERSION=2.0.1
# 产出: bin/ce-render-cfg-amd64, bin/ce-render-cfg-arm64
```

### 一键校验

```bash
bash scripts/verify.sh
# 依次执行: bash -n 全量语法检查 → shellcheck 静态分析 → go vet/build → 配置渲染冒烟测试
# 提交前和打包前各跑一次，全部通过退出码 0
```

shellcheck 本地安装: `brew install shellcheck`（macOS）/ `apt install shellcheck`（Debian 系）。

### 添加新中间件

1. 在 `opt/fit2cloud/external-compose/middleware/` 添加 `*-docker-compose.yml`（声明 `cmp-network: external: true`）
2. 在 `opt/fit2cloud/scripts/middleware/` 添加脚本，调用 `mw_init`，实现 `check_`/`install_`/`configure_`
3. 在 `service.sh` 的 `get_compose_files()` 中添加 `CE_EXTERNAL_*` 条件包含逻辑
4. 在 `install.env.example` 中添加 `CE_EXTERNAL_<NAME>` 开关、在 `runtime.env.example` 中添加连接参数
5. 在 `fit2cloud.properties.tpl` 中添加对应配置（使用 `{{ .CE_* | default "..." }}` 语法）
6. 如需密码模板，在 `conf/<name>/` 添加 `.tpl` 文件（`render.sh` 自动扫描渲染）
