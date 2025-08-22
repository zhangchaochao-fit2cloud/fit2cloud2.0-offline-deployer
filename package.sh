#!/usr/bin/env bash

#set -ex

# =============================================================================
# Fit2Cloud 2.0 打包脚本
# =============================================================================


set -e

# 获取脚本所在目录
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引入工具函数库
source "$BASE_DIR/opt/fit2cloud/scripts/common.sh"
source "$BASE_DIR/opt/fit2cloud/scripts/docker.sh"


# 显示帮助信息
show_help() {
    cat << EOF
Fit2Cloud 2.0 打包脚本

用法: $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -v, --version VERSION   版本号 [默认: 2.0.0]
    -b, --build-number NUM  构建号 [默认: 1]
    -r, --registry URL      镜像仓库地址 [默认: registry.fit2cloud.com]
    -o, --output-dir DIR    输出目录 [默认: ./dist]
    --dry-run               试运行模式
    --clean                 清理临时文件

示例:
    # 基本打包
    $0 -v 2.0.1 -b 100

    # 自定义镜像仓库
    $0 -r my-registry.com -v 2.0.1

    # 试运行模式
    $0 --dry-run -v 2.0.1

EOF
}

# 解析命令行参数
parse_args() {
    # 版本
    FIT2CLOUD_VERSION="2.0"
    BUILD_NUMBER="1"
    VERSION="master"
    # docker 镜像仓库地址
    REGISTRY_URL="registry.fit2cloud.com"
    # 输出目录
    OUTPUT_DIR="$BASE_DIR/dist"
    # 安装目录
    INSTALLER_DIR="$OUTPUT_DIR/installer"
    # 镜像打包目录
    DOCKER_IMAGES_DIR="$INSTALLER_DIR/docker-images"
    # 插件目录
    TMP_CLOUD_PLUGINS_DIR="$OUTPUT_DIR/cloud_plugins"
    # 插件目录
    CLOUD_PLUGINS_DIR="$INSTALLER_DIR/fit2cloud/data/plugins"
    # tools
    TOOLS_DIR="$INSTALLER_DIR/fit2cloud/tools"
    # 中间件目录
    MIDDLEWARE_DIR="$INSTALLER_DIR/fit2cloud/middleware_init"
    # 扩展包目录
    EXTENSIONS_DIR="$INSTALLER_DIR/extensions"
    # 插件包，默认全部
    PLUGIN_PACKAGES=""
    # 中间件包
    DEPLOYMENT_PACKAGES=""
    # 扩展包
    EXTENSION_PACKAGES=""

    BUILD_ID=""
    # 整包名
    PACKAGE_FILENAME=""
    # 整包全名
    FULL_PACKAGE_FILENAME=""
    # 整包 MD5 名
    MD5_PACKAGE_FILENAME=""

    # 插件包名
    PLUGIN_PACKAGE_FILENAME=""
    # 插件包全名
    FULL_PLUGIN_PACKAGE_FILENAME=""
    # 插件包 MD5 名
    MD5_PLUGIN_PACKAGE_FILENAME=""


    # 尝试运行
    DRY_RUN=false
    # 清理临时文件
    CLEAN_TEMP=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                FIT2CLOUD_VERSION="$2"
                shift 2
                ;;
            -b|--build-number)
                BUILD_NUMBER="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY_URL="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --from-docker-local)
                FROM_DOCKER_LOCAL_DIR="$2"
                shift 2
                ;;
            -p|--plugin-packages)
                PLUGIN_PACKAGES="$2"
                shift 2
                ;;
            -d|--deployment-packages)
                DEPLOYMENT_PACKAGES=($2)
                shift 2
            ;;
            -e|--extension-packages)
                EXTENSION_PACKAGES=($2)
                shift 2
            ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --clean)
                CLEAN_TEMP=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查前置条件
check_prerequisites() {
    log_info_inline "检查前置条件"

    # 检查必需的命令
    local required_commands=("docker" "docker-compose" "tar" "wget" "unzip")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_step_error "命令未找到: $cmd"
            exit 1
        fi
    done

    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_step_error "Docker 未运行或无法连接"
        exit 1
    fi

    # 检查网络连接
    if ! curl -s --connect-timeout 5 ${REGISTRY_URL} &> /dev/null; then
        log_step_warn "网络连接可能有问题"
        return
    fi

    log_ok
}

# 创建输出目录
create_output_dirs() {
    log_info_inline "创建输出目录"

    # 先清理上次的打包目录
    rm -rf "$OUTPUT_DIR"
    # 创建打包目录
    mkdir -p "$OUTPUT_DIR"
    # 打包目录
    mkdir -p "$INSTALLER_DIR"
    # Docker 镜像目录
    mkdir -p "$DOCKER_IMAGES_DIR"
    # 插件目录
    mkdir -p "$CLOUD_PLUGINS_DIR"
    # 扩展插件目录
    mkdir -p "$TMP_CLOUD_PLUGINS_DIR"
    # 中间件目录
    mkdir -p "$MIDDLEWARE_DIR"
    # 扩展包目录
    mkdir -p "$EXTENSIONS_DIR"

    log_ok
}

# 准备安装包信息
generate_package_file() {
    BUILD_TIME=$(date "+%Y%m%d%H%M")
    local today=$(date "+%Y.%m.%d")
    local platform=$(get_env_value PLATFORM)
    local build_version=${version}
    if [ -z ${build_version} ];then
      build_version="V3.1.${BUILD_NUMBER}-${VERSION}"
    fi
    BUILD_ID="${build_version} Build ${BUILD_TIME}"
    # 整包
    PACKAGE_FILENAME="cloudexplorer-${build_version}-${platform}-${today}"
    FULL_PACKAGE_FILENAME="${PACKAGE_FILENAME}.tar.gz"
    MD5_PACKAGE_FILENAME="${PACKAGE_FILENAME}.md5"

    # 插件包
    PLUGIN_PACKAGE_FILENAME="cloudexplorer-cloudplugins-${build_version}-${platform}-${today}"
    FULL_PLUGIN_PACKAGE_FILENAME="${PLUGIN_PACKAGE_FILENAME}.tar.gz"
    MD5_PLUGIN_PACKAGE_FILENAME="${PLUGIN_PACKAGE_FILENAME}.md5"
}

prepare_installer_files() {
    log_info_inline "准备安装文件"

    # 扩展插件目录
    if [ -d 'extensions' ];then
      mv extensions "$INSTALLER_DIR"
    fi

    # 复制基础文件
    cp -rp opt/* "$INSTALLER_DIR/"

    # 清理不需要的文件
    rm -rf "$INSTALLER_DIR/fit2cloud/data/mysql/*"

    # 移动二进制文件
    mv "$INSTALLER_DIR/fit2cloud/bin/fit2cloud/"* "$INSTALLER_DIR/"

    export CE_INSTALL_PATH="$BASE_DIR/opt"

    # 整包名称
    generate_package_file
    log_ok
}

# 下载工具
download_tools() {
    print_subtitle "下载工具..."
    download_docker "$TOOLS_DIR/docker"
}

# 复制插件
make_cloud_plugin() {
    if [[ -z "$PLUGIN_PACKAGES" ]]; then
        return
    fi

    print_subtitle "复制插件..."

    IFS=' ' read -r -a packages <<< "$PLUGIN_PACKAGES"

    for package_dir in "${packages[@]}"; do
        [[ ! -d "$package_dir" ]] && continue
        for plugin_file in "$package_dir"/*jar-with-dependencies.jar; do
            [[ ! -f "$plugin_file" ]] && continue
            plugin_name=$(basename "$plugin_file")
            short_name="${plugin_name/-2.0-jar-with-dependencies.jar/}"

            log_info_inline "$short_name"

            if [[ -z "$plugins" || "$plugins" == *"$short_name"* ]]; then
                cp -i "$plugin_file" "${CLOUD_PLUGINS_DIR}/"
            else
                cp -i "$plugin_file" "${TMP_CLOUD_PLUGINS_DIR}/"
            fi

            log_ok
        done
    done
}

make_middleware() {
    if [ "a$DEPLOYMENT_PACKAGES" == 'a' ];then
        return
    fi

    print_subtitle "复制部署包..."

    IFS=' ' read -r -a packages <<< "$DEPLOYMENT_PACKAGES"
    for package in "${packages[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
          filename=$(basename "$package")
          decode_filename=$(echo -e $(printf '%b' "${filename//%/\\x}"))
          log_info_inline "$decode_filename"
          log_step_success "跳过"
          continue
        fi
        wget --quiet --show-progress --progress=bar:force -O $MIDDLEWARE_DIR/pkg.zip $package
        unzip -O utf8 -d $MIDDLEWARE_DIR/middleware_init $MIDDLEWARE_DIR/pkg.zip
        rm -f $MIDDLEWARE_DIR/pkg.zip
        rm -rf $MIDDLEWARE_DIR/middleware_init/__MACOSX
    done
}

make_extensions() {
    if [ "a$EXTENSION_PACKAGES" == 'a' ];then
        return
    fi

    print_subtitle "复制扩展包..."

    IFS=' ' read -r -a packages <<< "$EXTENSION_PACKAGES"
    for package in "${packages[@]}"; do
        local filename=$(basename "$package")
        local decode_filename=$(echo -e $(printf '%b' "${filename//%/\\x}"))
        if [[ "$DRY_RUN" == "true" ]]; then
          log_info_inline "$decode_filename"
          log_step_success "跳过"
          continue
        fi
        wget --quiet --show-progress --progress=bar:force -O $EXTENSIONS_DIR/$decode_filename $package
    done
}

# 创建安装包
create_installer_package() {

    print_subtitle "创建安装包..."

#    local build_time=$(date "+%Y%m%d%H%M")
#    local today=$(date "+%Y.%m.%d")
#    local platform=$(get_env_value PLATFORM)
#    local build_version=${version}
#    if [ -z ${build_version} ];then
#      build_version="V3.1.${BUILD_NUMBER}-${VERSION}"
#    fi
#    local build_id="${build_version} Build ${build_time}"
    # 整包
#    local filename="cloudexplorer-${build_version}-${platform}-${today}"
#    local full_filename="${filename}.tar.gz"
#    local md5_filename="${filename}.md5"

    # 插件包
#    local plugin_filename="cloudexplorer-cloudplugins-${build_version}-${platform}-${today}"
#    local full_plugin_filename="${plugin_filename}.tar.gz"
#    local md5_plugin_filename="${plugin_filename}.md5"

    # 生成版本信息
    echo "$BUILD_ID" > "${INSTALLER_DIR}/fit2cloud/conf/version"

    cd "$OUTPUT_DIR"

#    if [[ "$DRY_RUN" != "true" ]]; then
    # 整包
    tar -zcf "$FULL_PACKAGE_FILENAME" installer
    md5sum "$FULL_PACKAGE_FILENAME" | awk '{print "md5: "$1}' > "$MD5_PACKAGE_FILENAME"

    # 插件包
    tar -zcf "$FULL_PLUGIN_PACKAGE_FILENAME" cloud_plugins
    md5sum "$FULL_PLUGIN_PACKAGE_FILENAME" | awk '{print "md5: "$1}' > "$MD5_PLUGIN_PACKAGE_FILENAME"

    log_success "安装包创建完成: $FULL_PACKAGE_FILENAME"
    log_success "MD5 校验文件: $MD5_PACKAGE_FILENAME"

    log_success "扩展包创建完成: $FULL_PLUGIN_PACKAGE_FILENAME"
    log_success "MD5 插件校验文件: $MD5_PLUGIN_PACKAGE_FILENAME"
#    else
#        log_step_success "跳过"
#    fi
}

# 清理临时文件
cleanup_temp_files() {
    if [[ "$CLEAN_TEMP" != "true" ]]; then
      return
    fi
    print_subtitle "清理临时文件..."
    log_info_inline "打包目录"
    rm -rf "${INSTALLER_DIR}"
    log_ok
    log_info_inline "插件目录"
    rm -rf "${TMP_CLOUD_PLUGINS_DIR}"
    log_ok
}

# 显示打包信息
show_package_info() {
    print_title "Fit2Cloud ${FIT2CLOUD_VERSION} 打包完成！"
#
#    local build_time=$(date "+%Y%m%d%H%M")
#    local filename="fit2cloud-cmp-installer-V${FIT2CLOUD_VERSION}.${BUILD_NUMBER}"
#    local full_filename="${filename}.tar.gz"

    cat << EOF

=============================================================================
打包信息
=============================================================================
版本: $FIT2CLOUD_VERSION
构建号: $BUILD_NUMBER
构建时间: $BUILD_TIME
镜像仓库: $REGISTRY_URL
输出目录: $OUTPUT_DIR
安装包: $FULL_PACKAGE_FILENAME

=============================================================================
文件位置
=============================================================================
安装包目录: $OUTPUT_DIR/$full_filename

=============================================================================

EOF
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"

    print_title "开始打包 Fit2Cloud 2.0..."

    # 检查前置条件
    check_prerequisites

    # 创建输出目录
    create_output_dirs

    # 准备安装器文件
    prepare_installer_files

    # 拉取 Docker 镜像
    pull_docker_images

    # 导出 Docker 镜像
    export_docker_images $DOCKER_IMAGES_DIR

    # 下载工具
    download_tools

    # 复制插件
    make_cloud_plugin

    # 复制中间件
    make_middleware

    # 复制扩展包
    make_extensions

    # 创建安装包
    create_installer_package

    # 清理临时文件
    cleanup_temp_files

    # 显示打包信息
    show_package_info
}

# 执行主函数
main "$@"
