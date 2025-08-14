#!/bin/bash
extension_file=$1
if [ "x$extension_file" == "x" ]; then
  echo "安装扩展模块 : fit2cloud-install-extension [FILE]"
  echo
  echo "示例 : fit2cloud-install-extension /tmp/fit2cloud-extension.tar.gz"
  exit 1;
fi

red=31
green=32
yellow=33
blue=34

function colorMsg()
{
  echo -e "\033[$1m $2 \033[0m"
}

installLog="/tmp/fit2cloud-extension-install.log"
fit2cloud_dir="/opt/fit2cloud"
fit2cloud_conf_dir="$fit2cloud_dir/conf/"
extension_dir="$fit2cloud_dir/extensions"

random_dir_name=`cat /dev/urandom | head -n 10 | md5sum | head -c 10`
tmp_dir="/tmp/f2c-extensions/$random_dir_name"
extension_tmp_dir="$tmp_dir/extension"


if [ ! -d "$tmp_dir" ]; then
  mkdir -p $tmp_dir
fi


printf "%-65s .......... " "解压扩展模块安装包"
tar zxvf $extension_file -C $tmp_dir >> $installLog 2>&1
colorMsg $green "[OK]"


for module_name in $(cat $extension_tmp_dir/docker-compose.yml | grep "container_name" | awk -F "container_name: " '{print $NF}'); do
  if [ ! "$service_name" ]; then
    service_name=$module_name
  fi
  module_name_list="$module_name_list $module_name"
done

for server_image in $(ls $extension_tmp_dir/*.tar); do
  printf "%-65s .......... " "加载扩展模块镜像 : $server_image"
  docker load -q -i $server_image >> $installLog 2>&1
  colorMsg $green "[OK]"
done

echo "安装扩展模块 : $service_name"
extension_name=`grep "image:" $extension_tmp_dir/docker-compose.yml | awk -F "/" '{print $NF}' | awk -F: '{print $1}' | head -n 1`
fit2cloud_extention_folder="$extension_dir/$extension_name/"
if [ ! -d "$fit2cloud_extention_folder" ]; then
  echo "扩展模块目录不存在，创建模块目录 : $fit2cloud_extention_folder"
  mkdir -p $fit2cloud_extention_folder
fi
\cp $extension_tmp_dir/docker-compose.yml $fit2cloud_extention_folder

extention_tmp_conf_folder="$extension_tmp_dir/conf"
fit2cloud_extention_conf_folder="$fit2cloud_conf_dir/$service_name/"
if [ -d "$extention_tmp_conf_folder" ]; then
  if [ ! -d "$fit2cloud_extention_conf_folder" ]; then
    printf "%-65s .......... " "创建扩展模块配置文件目录"
    mkdir -p "$fit2cloud_extention_conf_folder"
    colorMsg $green "[OK]"
  fi

  printf "%-65s .......... " "复制配置文件 : $conf_file"
  \cp -rf $extention_tmp_conf_folder/* $fit2cloud_extention_conf_folder
  colorMsg $green "[OK]"

fi

extention_tmp_install_script="$extension_tmp_dir/scripts/install.sh"
if [ -f $extention_tmp_install_script ]; then
  printf "%-65s .......... " "执行扩展模块初始化安装脚本 : $extention_tmp_install_script"
  bash $extention_tmp_install_script
  colorMsg $green "[OK]"
fi


printf "%-65s .......... " "启动扩展模块 : $service_name"
docker_compose_file_args="-f $fit2cloud_dir/docker-compose.yml"
for extension in $(ls $extension_dir); do
  current_extension_dir="$extension_dir/$extension"
  if [ ! -d $current_extension_dir ]; then
    continue
  fi

  for extension_file_name in $(ls $current_extension_dir); do
    extension_file="$current_extension_dir/$extension_file_name"
    if [ ! -f $extension_file ]; then
      continue
    fi

    if [ "$extension_file_name" == "docker-compose.yml" ]; then
      docker_compose_file_args="$docker_compose_file_args -f $extension_file"
    fi
  done
done
docker-compose $docker_compose_file_args up --no-recreate -d $module_name_list >> $installLog 2>&1
colorMsg $green "[OK]"

printf "%-65s .......... " "清理临时安装文件 : $service_name"
rm -rf $tmp_dir  >> $installLog 2>&1
colorMsg $green "[OK]"
