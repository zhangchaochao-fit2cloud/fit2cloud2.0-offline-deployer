#!/bin/bash
installerPath=/opt
systemName="FIT2CLOUD 云管平台 3.0"
upgradeLog="/tmp/fit2cloud-upgrade.log"

oldDockerComposeFile="$installerPath/fit2cloud/docker-compose.yml"
newDockerComposeFile="../fit2cloud/docker-compose.yml"
redisEnvFile="$installerPath/fit2cloud/conf/redis.env"
extensionInstallScript="/usr/bin/fit2cloud-install-extension"
extensionUpgradeScript="/usr/bin/fit2cloud-upgrade-extension"

red=31
green=32
yellow=33
blue=34

function printTitle()
{
  echo -e "\n\n**********\t ${1} \t**********\n"
}

function colorMsg()
{
  echo -e "\033[$1m $2 \033[0m"
}

function diffAndNoUpgradeImage()
{
    replace_image=$1
    is_upgrade=$2
    echo
    echo -ne "对比检查 compose $replace_image 镜像 \t........................ "
    # 检查镜像，是否有变化，如果有变化 使用原来的镜像
    old_image=$(cat ${oldDockerComposeFile} | grep image: | awk -F "image: " '{print $NF}' | grep $replace_image)
    new_image=$(cat ${newDockerComposeFile} | grep image: | awk -F "image: " '{print $NF}' | grep $replace_image)
    format_old_image=`echo $old_image | sed 's#\/#\\\/#g'`
    format_new_image=`echo $new_image | sed 's#\/#\\\/#g'`
    if [[ "${old_image}" != "${new_image}" ]] && [[ "x$is_upgrade" != "xyes" ]]; then
      sed -i "s/$format_new_image/$format_old_image/g" $newDockerComposeFile
      colorMsg $green "[OK]不升级 $replace_image 镜像"
    else
      colorMsg $green "[OK]"
    fi
}

cat << EOF
███████╗██╗████████╗██████╗  ██████╗██╗      ██████╗ ██╗   ██╗██████╗ 
██╔════╝██║╚══██╔══╝╚════██╗██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
█████╗  ██║   ██║    █████╔╝██║     ██║     ██║   ██║██║   ██║██║  ██║
██╔══╝  ██║   ██║   ██╔═══╝ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║     ██║   ██║   ███████╗╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
╚═╝     ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝                                                                    
EOF

versionInfo=`cat ../fit2cloud/conf/version`

colorMsg $yellow "\n\n开始升级 $systemName，版本 - $versionInfo\n"

chmod +x /etc/rc.d/rc.local

echo -ne "检查 FIT2CLOUD 配置文件 \t........................ " 
if [ ! -f "${oldDockerComposeFile}" ];then
	colorMsg $red "[ERROR] ${oldDockerComposeFile} 文件不存在！"
	exit 1
fi

if [ ! -f "${newDockerComposeFile}" ];then
	colorMsg $red "[ERROR] 升级包中缺少 docker-compose.yml 文件！"
	exit 1
fi


# step 1 - stop fit2cloud service
printTitle "停止 $systemName 服务"
echo -ne "停止 FIT2CLOUD 服务 \t........................ "
service fit2cloud stop >> $upgradeLog 2>&1
colorMsg $green "[OK]"

diffLine=`diff $oldDockerComposeFile $newDockerComposeFile | wc -l`
if [ "$diffLine" -eq "0" ];then
	colorMsg $green "[OK]"
else
  diffAndNoUpgradeImage mysql
	read -r -p "docker-compose.yml 文件有变化，是否需要替换[y/n]" input

	case $input in
	    [yY][eE][sS]|[yY])
			echo "Yes"
			echo "旧版本 docker-compose.yml 文件另存为 ${oldDockerComposeFile}.bak"

      # 升级 springboot 后 activity 库初始化必须加 nullCatalogMeansCurrent 这个参数
      nullCatalogMeansCurrent=`cat $installerPath/fit2cloud/conf/fit2cloud.properties | grep 'nullCatalogMeansCurrent=true' | wc -l`
      if [ "${nullCatalogMeansCurrent}" -eq 0 ];then
        sed -i '/^rdb.url=/ s/$/\&nullCatalogMeansCurrent=true/' $installerPath/fit2cloud/conf/fit2cloud.properties
      fi

			\mv $oldDockerComposeFile ${oldDockerComposeFile}.bak
			\cp $newDockerComposeFile $oldDockerComposeFile
			;;

	    *)
			echo "No"
			colorMsg $yellow "请检查升级包中的 docker-compose.yml 文件，如有版本变化模块将无法使用最新版本功能。"
	       		;;
	esac
fi

if [ ! -f "${redisEnvFile}" ];then
	cp -f ../fit2cloud/conf/redis.env $installerPath/fit2cloud/conf/redis.env
fi

# 拷贝 InfluxDB 数据目录和初始化脚本
influxdbDataDir=$installerPath/fit2cloud/data/influxdb
if [ ! -d ${influxdbDataDir} ];then
  mkdir -p ${influxdbDataDir}
fi

if [ ! -f "$installerPath/fit2cloud/conf/influxdb.conf" ];then
  \cp -f ../fit2cloud/conf/influxdb.conf $installerPath/fit2cloud/conf/influxdb.conf
  \cp -rp ../fit2cloud/bin/influxdb $installerPath/fit2cloud/bin/

cat >> $installerPath/fit2cloud/conf/fit2cloud.properties <<EOF

#influxdb
spring.influx.url=http://influxdb:8086
spring.influx.password=Password123@influxdb
spring.influx.user=fit2cloud
spring.influx.database=fit2cloud
EOF

fi

# 更新 运维工具
\cp fit2cloud.service /etc/init.d/fit2cloud

\cp -f f2cctl /usr/bin/f2cctl
chmod a+x /usr/bin/f2cctl

# 更新 compose，compose升级到了v2版本
\cp -f ../fit2cloud/tools/docker/bin/docker-compose /usr/bin/docker-compose
chmod a+x /usr/bin/docker-compose

# newExtensionInstallScript="fit2cloud-install-extension.sh"
# diffLine=`diff $extensionInstallScript $newExtensionInstallScript | wc -l`
# if [ "$diffLine" -ne "0" ];then
# 	echo -ne "更新扩展模块安装脚本 \t........................ "
# 	\cp -f $newExtensionInstallScript $extensionInstallScript
# 	colorMsg $green "[OK]"
# fi

# newExtensionUpgradeScript="fit2cloud-upgrade-extension.sh"
# diffLine=`diff $extensionUpgradeScript $newExtensionUpgradeScript | wc -l`
# if [ "$diffLine" -ne "0" ];then
# 	echo -ne "更新扩展模块升级脚本 \t........................ "
# 	\cp -f $newExtensionUpgradeScript $extensionUpgradeScript
# 	colorMsg $green "[OK]"
# fi

echo "" > $upgradeLog
\cp -rpf ../fit2cloud/middleware_init/* $installerPath/fit2cloud/middleware_init/

# step 2 - load fit2cloud 2.0 docker images
printTitle "加载 $systemName 最新镜像"
docker_images_folder="../docker-images"
for docker_image in ${docker_images_folder}/*; do
  temp_file=`basename $docker_image`
  printf "加载镜像 %-45s ........................ " $temp_file
  docker load -q -i ${docker_images_folder}/$temp_file >> $upgradeLog 2>&1
  printf "\e[32m[OK]\e[0m \n"
done

# step 3 - remove old docker images
printTitle "移除 $systemName 旧版本镜像"
invalid_images=`docker images -f "dangling=true" -q`
for s in ${invalid_images[@]}; do
  printf "移除镜像 %-45s ........................ " ${s}
  docker rmi -f ${s} >> $upgradeLog 2>&1
  printf "\e[32m[OK]\e[0m \n"
done

# step 3.1 upgrade场景，补充文件夹
if [ ! -d "$installerPath/fit2cloud/data/upload" ];then
  mkdir -p $installerPath/fit2cloud/data/upload
fi

# step 4 - start fit2cloud
printTitle "启动 $systemName"
cp -f ../fit2cloud/conf/version $installerPath/fit2cloud/conf/version
echo -ne "启动 FIT2CLOUD 服务 \t........................ " 
service fit2cloud start >> $upgradeLog 2>&1
colorMsg $green "[OK]"

if [ -d "$installerPath"/fit2cloud/../extensions ];then
  cd "$installerPath"/fit2cloud/../extensions
  extensions=($(ls))
  sleep 60
  echo -e " 更新扩展模块 \t........................ "
  while 'true';do
    startingNum=$(service fit2cloud status | grep starting | wc -l)
    if [ "$startingNum" -eq 0 ];then
      for i in ${extensions[@]} ; do
          read -p "是否 安装/更新 扩展模块 ${i}? [y/n](默认n):" word
          if echo "$word" | grep -qwi "y";then
              /bin/f2cctl install-module $i
          fi
      done
      break
    else
      sleep 10
    fi
  done
  colorMsg $green "[OK]"
fi

echo
echo "********************************************************************************************"
echo -e "\t${systemName} 升级已完成，请在服务完全启动后(大概需要等待5分钟左右)访问"
echo "********************************************************************************************"
echo
