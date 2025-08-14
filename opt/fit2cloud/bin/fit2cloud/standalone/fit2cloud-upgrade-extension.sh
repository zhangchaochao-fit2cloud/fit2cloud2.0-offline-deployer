#!/bin/bash
extension_file=$1

if [ "x$extension_file" == "x" ]; then
  echo "升级扩展模块 : fit2cloud-upgrade-extension [FILE]"
  echo
  echo "示例 : fit2cloud-upgrade-extension /tmp/fit2cloud-extension.tar.gz"
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

upgradeLog="/tmp/fit2cloud-extension-upgrade.log"
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
tar zxvf $extension_file -C $tmp_dir >> $upgradeLog 2>&1
colorMsg $green "[OK]"

for module_name in $(cat $extension_tmp_dir/docker-compose.yml | grep "container_name" | awk -F "container_name: " '{print $NF}'); do
  if [ ! "$service_name" ]; then
    service_name=$module_name
  fi
  module_name_list="$module_name_list $module_name"
done

extension_name=`grep "image:" $extension_tmp_dir/docker-compose.yml | awk -F "/" '{print $NF}' | awk -F: '{print $1}' | head -n 1`
fit2cloud_extention_folder="$extension_dir/$extension_name"
if [ ! -d "$fit2cloud_extention_folder" ]; then
  colorMsg $red "未找到指定扩展模块对应的扩展目录"
  exit 1;
fi

for server_image in $(ls $extension_tmp_dir/*.tar); do
  printf "%-65s .......... " "升级扩展模块镜像 : $server_image"
  docker load -q -i $server_image >> $upgradeLog 2>&1
  colorMsg $green "[OK]"
done

printf "%-65s .......... " "停止原有服务 : $module_name_list"
docker-compose -f $fit2cloud_dir/docker-compose.yml -f $fit2cloud_extention_folder/docker-compose.yml rm -sf $module_name_list >> $upgradeLog 2>&1
colorMsg $green "[OK]"

printf "%-65s .......... " "删除无用镜像 : $service_name"
invalid_images=`docker images -f "dangling=true" -q`
for s in ${invalid_images[@]}; do
  docker rmi -f ${s} >> $upgradeLog 2>&1
done
colorMsg $green "[OK]"

printf "%-65s .......... " "升级扩展模块 : $service_name"
\cp -f $fit2cloud_extention_folder/docker-compose.yml $fit2cloud_extention_folder/docker-compose.yml.bak
\cp -f $extension_tmp_dir/docker-compose.yml $fit2cloud_extention_folder
colorMsg $green "[OK]"

extention_tmp_upgrade_script="$extension_tmp_dir/scripts/upgrade.sh"
if [ -f $extention_tmp_upgrade_script ]; then
  printf "%-65s .......... " "执行扩展模块初始化升级脚本 : $extention_tmp_upgrade_script"
  bash $extention_tmp_upgrade_script
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
docker-compose $docker_compose_file_args up --no-recreate -d $module_name_list >> $upgradeLog 2>&1
colorMsg $green "[OK]"

printf "%-65s .......... " "清理临时升级文件 : $service_name"
rm -rf $tmp_dir  >> $upgradeLog 2>&1
colorMsg $green "[OK]" 
