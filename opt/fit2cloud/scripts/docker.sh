#!/bin/bash

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# compose 目录
COMPOSE_DIR="$SCRIPT_DIR/.."
EXT_COMPOSE_DIR="$SCRIPT_DIR/../external-compose"

# env 环境变量文件
ENV_FILE="$SCRIPT_DIR/../.env"

# 远程下载 docker 地址
DOCKER_PACKAGE_URL="https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker.zip"
DOCKER_PACKAGE_URL_ARM64="https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker-arm64.zip"
DOCKER_PACKAGE_URL_RHEL8="https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker-rhel8.tar.gz"

source "$SCRIPT_DIR/common.sh"

# 生成 compose 参数
get_docker_compose_args() {
    local compose="$COMPOSE_DIR/docker-compose.yml"
    local base_compose="$EXT_COMPOSE_DIR/base-docker-compose.yml"
    local middleware_dir="$EXT_COMPOSE_DIR/middleware"
    local ce_mode=$(get_env_value CE_MODE)
    local compose_args="--env-file $ENV_FILE -f $compose"

    if [ "1${ce_mode}" == "1ha" ]; then
        compose_args="$compose_args -f $EXT_COMPOSE_DIR/ha-docker-compose.yml"
    else
        compose_args="$compose_args -f $EXT_COMPOSE_DIR/base-docker-compose.yml"
        for middleware in $(ls $middleware_dir); do
            middleware_compose="$middleware_dir/$middleware"
            if [ ! -f $middleware_compose ]; then
                continue
            fi
            compose_args="$compose_args -f $middleware_compose"
        done
    fi

    echo "$compose_args"
}

# 获取执行命令
get_docker_compose_exe() {
    # 获取构建参数
    local args=$(get_docker_compose_args)

    echo "docker-compose $args"
}

# 获取所有服务镜像
get_all_images() {
    # 获取构建参数
    local exe=$(get_docker_compose_exe)

    # 获取镜像列表
    local image_names=$($exe config | grep "image:" | grep "$args" | awk '{print $2}' | tr -d '"')

    echo $image_names
}

# 获取所有服务端口
get_all_ports() {
    # 获取构建参数
    local exe=$(get_docker_compose_exe)

    # 获取镜像列表
    local image_names=$($exe config | grep -A 1 "ports:$" | grep "\-.*:" | awk -F":" '{print $1}' | awk -F" " '{print $2}')

    echo $image_names
}

# 拉取 Docker 镜像
pull_docker_images() {
    print_subtitle "拉取 Docker 镜像..."

    # 获取构建镜像
    local compose_images=$(get_all_images)
    # 平台架构
    local platform=$(get_env_value PLATFORM)

    # 拉取镜像
    for image_name in ${compose_images}; do
        tag_name=$(echo "${image_name}" | awk -F "/" '{print $3}')
        log_info_inline "${tag_name}"
        if [[ "$DRY_RUN" != "true" ]]; then
#            output=$(docker pull --platform="linux/${platform}" "${image_name}" 2>&1 >/dev/null)
#            if [[ $? -ne 0 ]]; then
#                log_step_error "$output"
#                exit 1
#            fi
            docker pull --platform="linux/${platform}" "${image_name}" >/dev/null 2>&1 || {
                log_step_error "异常"
                exit 1
            }
            log_ok
        else
            log_step_success "跳过"
        fi
    done
}

# 导出 Docker 镜像
export_docker_images() {
    print_subtitle "导出 Docker 镜像..."

    local images_dir="$1"
    if [[ -z "$images_dir" ]]; then
        log_warn "没有指定 Docker 导出目录"
        return
    fi

    cd "$images_dir"
    # 获取构建镜像
    compose_images=$(get_all_images)

    # 导出镜像
    for image_name in ${compose_images}; do
      local name=$(echo "$image_name" | awk -F"/" '{ print $NF }')
      log_info_inline "${name}"
      if [[ "$DRY_RUN" != "true" ]]; then
          docker save -o "${name}.tar" "$image_name" >/dev/null 2>&1 || {
              log_step_error "异常"
              exit 1
          }
          log_ok
      else
          log_step_success "跳过"
      fi
    done
}

download_local_docker() {
    # 平台架构
    local platform=$(get_env_value PLATFORM)
    local docker_tools_dir=$1
    local docker_package=$2
    local docker_zip=""
    local redhat_docker_tar="${FROM_DOCKER_LOCAL_DIR}/docker-rhel8.tar.gz"

    if [[ "${platform}" == "arm64" ]]; then
        docker_zip=${FROM_DOCKER_LOCAL_DIR}/docker-arm64.zip
    else
        docker_zip=${FROM_DOCKER_LOCAL_DIR}/docker.zip
    fi

    # 判断 docker 文件是否存在
    if [ -f ${docker_zip} ]; then
        log_step_error "本地 Docker 不存在，请检查：${docker_zip}"
        exit 1
    fi

    # 复制 docker 到指定文件夹
    cp -f ${docker_zip} ${docker_tools_dir}/${docker_package}

    cp -f ${redhat_docker_tar} ${docker_tools_dir}/docker-rhel8.tar.gz
}

download_remote_docker() {
    # 平台架构
    local platform=$(get_env_value PLATFORM)
    local docker_tools_dir=$1
    local docker_package=$2

    DOCKER_PACKAGE_URL=$DOCKER_PACKAGE_URL
    if [[ "${platform}" == "arm64" ]]; then
      DOCKER_PACKAGE_URL=$DOCKER_PACKAGE_URL_ARM64
    fi

    cd ${docker_tools_dir}

    # 下载远程 docker
    wget --quiet --show-progress --progress=bar:force -O "./${docker_package}" "${DOCKER_PACKAGE_URL}"

    # 下载 redhat 版本 docker
    wget --quiet --show-progress --progress=bar:force -O "./docker-rhel8.tar.gz" "${DOCKER_PACKAGE_URL_RHEL8}"

    cd -
}

# 下载 docker
download_docker() {
    log_info_inline "下载Docker安装包"
    # 平台架构
    local platform=$(get_env_value PLATFORM)
    # docker tools 包
    local docker_package="docker_${platform}.zip"

    local docker_tools_dir="$1"
    if [[ -z "$docker_tools_dir" ]]; then
        log_step_error "没有指定 Docker 下载目录"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
      log_step_success "跳过"
      return
    fi

    # 本地 docker 目录没有配置，默认从远程获取
    if [[ -d "${FROM_DOCKER_LOCAL_DIR}" ]];then
      download_local_docker $docker_tools_dir $docker_package
    else
      download_remote_docker $docker_tools_dir $docker_package
    fi

     # 解压
    cd ${docker_tools_dir}
    unzip "${docker_package}"
    rm -rf "${docker_package}"
    rm -rf __MACOSX

    # redhat 版本
    cp -f ${docker_tools_dir}/docker-rhel8.tar.gz ${TOOLS_DIR}/docker/docker-rhel8.tar.gz
    tar -zxvf docker-rhel8.tar.gz
    rm -rf docker-rhel8.tar.gz

    # 回到上次的目录
    cd -

    log_ok
}

# 获取 Docker 存储目录
get_docker_dir() {
    docker info --format '{{.DockerRootDir}}' 2>/dev/null
}

# Docker 检测
check_docker() {
    log_info_inline "Docker 检测..."
    if ! command -v docker >/dev/null 2>&1; then
        log_step_error "未安装"
        return 1
    else
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null | cut -d. -f1)
        if [[ -z "$docker_version" ]]; then
            log_step_error "无法获取版本"
            return 1
        elif (( docker_version < 18 )); then
            log_step_error"版本需 >= 18"
            return 1
        else
            docker_dir=$(get_docker_dir)
            log_step_success "OK 存储目录：$docker_dir"
        fi
    fi
}

# Docker compose 检测
check_docker_compose() {
    log_info_inline "Docker compose 检测..."
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_step_error "未安装"
        return 1
    else
        log_ok
        return 0
    fi
}

# 安装 docker
install_docker() {
    print_subtitle "安装 Docker 运行时环境..."

    if [[ -z "$hasDocker" ]]; then
      if [ ! -f "$dockerConfigFile" ]; then
        create_docker_config
      fi

      chmod -R +x ../fit2cloud/tools/docker/bin/

      if [[ $majorVersion == 7 || -f /etc/kylin-release || $majorVersion == 20 || $majorVersion == 22 || $majorVersion == 24 ]]; then
        setup_docker_files_centos7
      elif [[ $majorVersion == 8 ]]; then
        install_rpms_centos8
      else
        log_error "操作系统版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x, Ubuntu 20/22/24"
        exit 1
      fi

      echo -ne "Docker \t\t\t........................ "
      colorMsg $green "[OK] 存储目录：$dockerPath"
    else
      echo -ne "Docker \t\t\t........................ "
      colorMsg $green "[OK] 已存在 Docker 运行时环境，跳过安装"
    fi

    start_enable_docker
}

# 安装 docker
install_docker_compose() {
    print_subtitle "导出 Docker 镜像..."

    local images_dir="$1"
    if [[ -z "$images_dir" ]]; then
        log_warn "没有指定 Docker 导出目录"
        return
    fi

    cd "$images_dir"
    # 获取构建镜像
    compose_images=$(get_all_images)

    # 导出镜像
    for image_name in ${compose_images}; do
      local name=$(echo "$image_name" | awk -F"/" '{ print $NF }')
      log_info_inline "${name}"
      if [[ "$DRY_RUN" != "true" ]]; then
          docker save -o "${name}.tar" "$image_name" >/dev/null 2>&1 || {
              log_step_error "异常"
              exit 1
          }
          log_ok
      else
          log_step_success "跳过"
      fi
    done
}


config_docker() {
    log_info "配置 Docker 服务..."

    # 创建配置目录
    mkdir -p "$DOCKER_CONFIG_DIR"

    # 创建配置文件
    cat > "$DOCKER_CONFIG_DIR/daemon.json" << EOF
{
  "data-root": "$DOCKER_DATA_DIR",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "insecure-registries": [],
  "registry-mirrors": []
}
EOF

    # 重启 Docker 服务
    systemctl restart docker

    log_info "Docker 配置完成"
}


# Docker 是否存在
check_docker_exists() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Docker 检测
check_docker() {
    log_info_inline "Docker 检测..."
    if ! command -v docker >/dev/null 2>&1; then
        log_ok
        return 0
    fi

    # 获取 Docker 主版本号
    local dockerVersion
    dockerVersion=$(docker info --format '{{.ServerVersion}}' 2>/dev/null | awk -F. '{print $1}')
    if [[ -z "$dockerVersion" ]]; then
        log_step_error "无法获取 Docker 版本"
        return 1
    fi

    if (( dockerVersion < 18 )); then
        log_step_error "Docker 版本需要 18 以上"
        return 1
    fi

    local dockerDir
    dockerDir=$(get_docker_dir)
    log_step_success "存储目录：$dockerDir，请确保目录空间充足"
}


check_docker_compose() {
    echo -ne "docker-compose 检测 \t........................ "

    if ! command -v docker-compose >/dev/null 2>&1; then
        colorMsg $red "[ERROR] 未安装 docker-compose"
        validationPassed=0
        return
    fi

    colorMsg $green "[OK]"
}