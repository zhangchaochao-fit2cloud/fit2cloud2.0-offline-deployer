#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../../opt/fit2cloud/scripts/common.sh"

create_package() {
    print_title "步骤 5/5: 创建安装包"

    local output_dir="$1"
    local installer_dir="$2"
    local build_id="$3"
    local platform="$4"
    local report_file="$5"

    echo "$build_id" > "${installer_dir}/fit2cloud/conf/version"

    local build_time=$(date "+%Y%m%d%H%M")
    local today=$(date "+%Y.%m.%d")
    local build_version=$(echo "$build_id" | awk '{print $1}')

    local package_filename="cloudexplorer-${build_version}-${platform}-${today}"
    local full_package_filename="${package_filename}.tar.gz"
    local md5_package_filename="${package_filename}.md5"

    local plugin_package_filename="cloudexplorer-cloudplugins-${build_version}-${platform}-${today}"
    local full_plugin_package_filename="${plugin_package_filename}.tar.gz"
    local md5_plugin_package_filename="${plugin_package_filename}.md5"

    # 生成包清单 manifest.txt：安装/升级时用于包完整性校验
    # 镜像行保持 md5sum 标准格式（hash  文件名），安装侧 --verify-images 可直接 md5sum -c
    {
        echo "version=${build_id}"
        echo "platform=${platform}"
        echo "build_time=${build_time}"
        # 记录 Python 实验版本信息
        if [[ "${WITH_PYTHON:-false}" == "true" && -f "${installer_dir}/fit2cloud/scripts_py/.version" ]]; then
            echo "python_version=experimental"
            echo "python_build=$(grep '^build_version=' "${installer_dir}/fit2cloud/scripts_py/.version" | head -1 | cut -d= -f2)"
            echo "python_build_time=$(grep '^build_time=' "${installer_dir}/fit2cloud/scripts_py/.version" | head -1 | cut -d= -f2)"
        fi
        if [[ -d "${installer_dir}/docker-images" ]]; then
            (cd "${installer_dir}/docker-images" && md5sum ./*.tar 2>/dev/null)
        fi
    } > "${installer_dir}/fit2cloud/manifest.txt"
    log_info "包清单已生成: fit2cloud/manifest.txt"

    cd "$output_dir"

    if [[ -d "$installer_dir" ]]; then
        tar -zcf "$full_package_filename" installer
        md5sum "$full_package_filename" | awk '{print "md5: "$1}' > "$md5_package_filename"
        log_success "安装包: $full_package_filename"
    fi

    local cloud_plugins_dir="$output_dir/cloud_plugins"
    if [[ -d "$cloud_plugins_dir" && "$(ls -A "$cloud_plugins_dir" 2>/dev/null)" ]]; then
        tar -zcf "$full_plugin_package_filename" cloud_plugins
        md5sum "$full_plugin_package_filename" | awk '{print "md5: "$1}' > "$md5_plugin_package_filename"
        log_success "插件包: $full_plugin_package_filename"
    fi

    cd - > /dev/null

    if [[ -n "$report_file" ]]; then
        cat > "$report_file" <<EOF
{
  "package": "$full_package_filename",
  "md5": "$md5_package_filename",
  "plugin_package": "$full_plugin_package_filename",
  "build_time": "$build_time"
}
EOF
    fi
}

copy_plugins() {
    print_subtitle "复制插件..."

    local plugin_packages="$1"
    local cloud_plugins_dir="$2"

    if [[ -z "$plugin_packages" ]]; then
        return
    fi

    ensure_dir "$cloud_plugins_dir"

    IFS=' ' read -r -a packages <<< "${plugin_packages//,/ }"
    for package_dir in "${packages[@]}"; do
        [[ ! -d "$package_dir" ]] && continue
        for plugin_file in "$package_dir"/*jar-with-dependencies.jar; do
            [[ ! -f "$plugin_file" ]] && continue
            local plugin_name=$(basename "$plugin_file")
            local short_name="${plugin_name/-2.0-jar-with-dependencies.jar/}"
            log_info_inline "$short_name"
            cp "$plugin_file" "${cloud_plugins_dir}/"
            log_ok
        done
    done
}

copy_middleware() {
    print_subtitle "复制部署包..."

    local deployment_packages="$1"
    local middleware_dir="$2"

    if [[ -z "$deployment_packages" ]]; then
        return
    fi

    ensure_dir "$middleware_dir"

    IFS=' ' read -r -a packages <<< "${deployment_packages//,/ }"
    for package in "${packages[@]}"; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            local filename=$(basename "$package")
            log_info_inline "$filename"
            log_step_success "跳过"
            continue
        fi
        wget --quiet --show-progress --progress=bar:force -O "$middleware_dir/pkg.zip" "$package"
        unzip -O utf8 -d "$middleware_dir/middleware_init" "$middleware_dir/pkg.zip" >/dev/null 2>&1
        rm -f "$middleware_dir/pkg.zip"
        rm -rf "$middleware_dir/middleware_init/__MACOSX"
    done
}

copy_extensions() {
    print_subtitle "复制扩展包..."

    local extension_packages="$1"
    local extensions_dir="$2"

    if [[ -z "$extension_packages" ]]; then
        return
    fi

    ensure_dir "$extensions_dir"

    IFS=' ' read -r -a packages <<< "${extension_packages//,/ }"
    for package in "${packages[@]}"; do
        local filename=$(basename "$package")
        local decode_filename=$(echo -e "$(printf '%b' "${filename//%/\\x}")")
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info_inline "$decode_filename"
            log_step_success "跳过"
            continue
        fi
        wget --quiet --show-progress --progress=bar:force -O "$extensions_dir/$decode_filename" "$package"
    done
}
