#!/bin/bash
#提示用户是否需要安装文件服务器MinIO
install_minio=true
minio_port_valid=false

installerPath=/opt
installLog="/tmp/fit2cloud-install.log"
dockerPath="$installerPath/fit2cloud/docker"
dockerConfigFolder="/etc/docker"
dockerConfigFile="$dockerConfigFolder/daemon.json"
ips=`ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p'`

red=31
green=32
yellow=33
blue=34
validationPassed=1
validationWarning=1

if [ "$1" = "-s" ];then
    nohup bash install-silent.sh >> install.log 2>&1 &
    exit 0
fi

function printTitle()
{
  echo -e "\n\n**********\t ${1} \t**********\n"
}

function printSubTitle()
{
  echo -e "------\t \033[${blue}m ${1} \033[0m \t------\n"
}


function colorMsg()
{
  echo -e "\033[$1m $2 \033[0m"
}

function checkPort()
{
    hasLsof=`which lsof 2>&1`
    if [[ "${hasLsof}" =~ "no lsof" ]]; then
        hasNetstat=`which netstat 2>&1`
        if [[ "${hasNetstat}" =~ "no netstat" ]]; then
            hasSs=`which ss 2>&1`
            if [[ "${hasSs}" =~ "no ss" ]]; then
                colorMsg $red "[WARNING] 没有找到 lsof、netstat 或 ss 命令，忽略端口检测"
                return 0
            else
                record=`ss -nlt | awk -F' ' '{print $4}' | grep "^[[:graph:]]*:\$1$" | wc -l`
            fi
        else
            record=`netstat -nplt | awk -F' ' '{print $4}' | grep "^[[:graph:]]*:\$1$" | wc -l`
        fi
    else
        record=`lsof -i:$1 | grep LISTEN | wc -l`
    fi

    echo -ne "$1 端口 \t\t........................ "
    if [ "$record" -eq "0" ]; then
        colorMsg $green "[OK]"
    else
        validationPassed=0
        colorMsg $red "[被占用]"
    fi
}

function checkMinIOPort()
{
    hasLsof=`which lsof 2>&1`
    if [[ "${hasLsof}" =~ "no lsof" ]]; then
        hasNetstat=`which netstat 2>&1`
        if [[ "${hasNetstat}" =~ "no netstat" ]]; then
            hasSs=`which ss 2>&1`
            if [[ "${hasSs}" =~ "no ss" ]]; then
                colorMsg $red "[WARNING] 没有找到 lsof、netstat 或 ss 命令，忽略MinIO端口检测"
                minio_port_valid=true
                return 0
            else
                record=`ss -tuln | grep ":$1" | wc -l`
            fi
        else
            record=`netstat -nplt | awk -F' ' '{print $4}'| grep "^[[:graph:]]*:\$1$" | wc -l`
        fi
    else
        record=`lsof -i:$1 | grep LISTEN | wc -l`
    fi

    echo -ne "$1 端口 \t\t........................ "
    if [ "$record" -eq "0" ]; then
        colorMsg $green "[OK]"
        minio_port_valid=true
    else
        colorMsg $red "[被占用]"
        minio_port_valid=false
    fi
}

function open_port(){
    if test $1;then
        systemctl status firewalld > /dev/null 2>&1
        if [[ $? -eq 0 ]];then
         echo -ne "打开防火墙端口$1 \t\t........................ "
         checkPort=`firewall-cmd --list-all | grep -w ports | grep -w $1`
         if [[ ${checkPort} == "" ]]; then
           firewall-cmd --zone=public --add-port=$1/tcp --permanent > /dev/null
           firewall-cmd --reload  > /dev/null
           systemctl restart docker > /dev/null 2>&1
           colorMsg ${green} "[OK]"
         else
            colorMsg ${green} "[OK]"
         fi
        fi
    fi
}

function get_docker_dir(){
    echo "$(docker info | grep "Docker Root Dir" | awk -F ': ' '{print $2}')"
}

# 根据用户输入去修改docker、MinIO、cmp的安装路径
# shellcheck disable=SC2162
read -p "CloudExplorer将安装到：$installerPath/fit2cloud，如需更改请输入自定义路径，否则按回车继续:" ce_Path
# shellcheck disable=SC2236
if [ ! -n "$ce_Path" ] ;then
  echo "使用默认安装路径$installerPath/fit2cloud"
else
  echo "使用自定义安装路径$ce_Path"
  installerPath=${ce_Path}
  dockerPath="$installerPath/fit2cloud/docker"
  if [ -d ${ce_Path} ];then
    # 修改MinIO安装脚本的修改f2c配置文件的路径
    sed -i 's#f2c_install_dir="/opt"#f2c_install_dir="'"$installerPath"'"#g' ../fit2cloud/tools/minio/minio-install.sh
    # 修改docker的安装脚本路径
    sed -i 's#dockerPath="/opt/fit2cloud/docker"#dockerPath="'"$installerPath/fit2cloud/docker"'"#g' ../fit2cloud/tools/docker/docker-install.sh
    # 修改f2cctl文件中路径
    sed -i 's#work_dir="/opt/fit2cloud"#work_dir="'"$installerPath/fit2cloud"'"#g' f2cctl
    # 修改fit2cloud服务启动路径
    sed -i 's#f2c_install_dir="/opt"#f2c_install_dir="'"$installerPath"'"#g' fit2cloud.service
    # 修改扩展包安装时的路径
    sed -i 's#fit2cloud_dir="/opt/fit2cloud"#fit2cloud_dir="'"$installerPath/fit2cloud"'"#g' fit2cloud-install-extension.sh
    sed -i 's#fit2cloud_dir="/opt/fit2cloud"#fit2cloud_dir="'"$installerPath/fit2cloud"'"#g' fit2cloud-upgrade-extension.sh
    # 修改升级升级脚本
    sed -i 's#installerPath=/opt#installerPath="'"$installerPath"'"#g' upgrade.sh
    # 修改docker-compose文件的环境变量
    sed -i 's#installerPath=/opt#installerPath="'"$installerPath"'"#g' ../fit2cloud/.env
    # 修改telegraf地址
    sed -i 's#installerPath=/opt#installerPath="'"$installerPath"'"#g' ../fit2cloud/tools/telegraf/telegraf-install.sh
  else
    echo "输入的目录不存在，退出安装~"
    exit 1
  fi
fi


read -p "是否安装MinIO服务器? [y/n](默认y):" word
if echo "$word" | grep -qwi "n"
then
  install_minio=false
  echo "不安装文件服务器,请配置已有的仓库(该仓库需要允许重复部署:设置为allowredeploy)"
  config=$installerPath/fit2cloud/conf/fit2cloud.properties
  read -p "仓库地址（eg: http://10.1.13.111:9001）:" repo
  echo "\n" >> $config
  echo "minio.endpoint=$repo" >> $config
  read -p "accessKey:" minio_ak
  echo minio.accessKey=$minio_ak >> $config
  read -p "secretKey:" minio_sk
  echo minio.secretKey=$minio_sk >> $config
  read -p "bucket:" bucket
  echo minio.bucket.default=$bucket >> $config
  echo "已写入配置，可在 管理中心/系统设置/系统参数中搜索 MinIO 进行管理.\n"
else
  while true;do
    read -p "MinIO 将使用默认安装路径$installerPath/fit2cloud，如需更改请输入自定义安装路径:" folder
    if [ ! -n "$folder" ] ;then
      echo "使用默认安装路径$installerPath/fit2cloud"
      folder="$installerPath/fit2cloud"
    else
      echo "使用自定义安装路径$folder"
    fi

    while true;do
    read -p "MinIO将使用默认访问端口9001，如需更改请输入自定义端口:" port
      if [ -n "$port" ] ;then
        if [[ $port =~ ^[0-9]*$ ]]
        then
          echo "检测$port端口是否被占用"
          checkMinIOPort $port
          if $minio_port_valid ;then
            echo "使用自定义端口$port"
            break
          fi
        else
          read -p "自定义端口只允许输入纯数字，请重新输入:" port
        fi
      else
        port=9001
        echo "检测$port端口是否被占用"
        checkMinIOPort $port
        if $minio_port_valid ;then
          echo "使用默认端口9001"
          break
        fi
      fi
    done

    read -p "确认MinIO安装使用安装路径:$folder/MinIO和端口:$port? [y/n](默认y)" sure
    if ! echo "$sure" | grep -qwi "n"
    then
      break
    fi
  done
fi


echo
cat << EOF
███████╗██╗████████╗██████╗  ██████╗██╗      ██████╗ ██╗   ██╗██████╗
██╔════╝██║╚══██╔══╝╚════██╗██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
█████╗  ██║   ██║    █████╔╝██║     ██║     ██║   ██║██║   ██║██║  ██║
██╔══╝  ██║   ██║   ██╔═══╝ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║     ██║   ██║   ███████╗╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
╚═╝     ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝
EOF

echo "" > $installLog

systemName="FIT2CLOUD 云管平台 3.0"
versionInfo=`cat ../fit2cloud/conf/version`

colorMsg $yellow "\n\n开始安装 $systemName，版本 - $versionInfo"

printTitle "${systemName} 安装环境检测"

#root用户检测
echo -ne "root 用户检测 \t\t........................ "
isRoot=`id -u -n | grep root | wc -l`
if [ "x$isRoot" == "x1" ];then
  colorMsg $green "[OK]"
else
  colorMsg $red "[ERROR] 请用 root 用户执行安装脚本"
  validationPassed=0
fi


#操作系统检测
echo -ne "操作系统检测 \t\t........................ "

if [ -f /etc/redhat-release ]; then
  osVersion=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+')
  majorVersion=$(echo $osVersion | awk -F. '{print $1}')
  minorVersion=$(echo $osVersion | awk -F. '{print $2}')
  if [ "x$majorVersion" == "x" ]; then
    colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x, Ubuntu 20/22/24 版本 64 位"
    validationPassed=0
  else
    if [[ $majorVersion != 7 ]] && [[ $majorVersion != 8 ]]; then
      colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x, Ubuntu 20/22/24 版本 64 位"
      validationPassed=0
    else
      colorMsg $green "[OK]"
    fi
  fi
elif [ -f /etc/kylin-release ]; then
  colorMsg $green "[OK]"
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  if [[ $ID == "ubuntu" ]]; then
    osVersion=$VERSION_ID
    majorVersion=$(echo $osVersion | awk -F. '{print $1}')
    if [[ $majorVersion == 20 ]] || [[ $majorVersion == 22 ]] || [[ $majorVersion == 24 ]]; then
      colorMsg $green "[OK]"
    else
      colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 Ubuntu 20.x/22.x/24.x 版本 64 位"
      validationPassed=0
    fi
  elif [[ $ID == "openEuler" ]]; then
    osVersion=$VERSION_ID
    majorVersion=$(echo $osVersion | awk -F. '{print $1}')
    if [[ $majorVersion == 22 ]] || [[ $majorVersion == 23 ]]; then
      colorMsg $green "[OK]"
    else
      colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 EulerOS 22.x/23.x 版本 64 位"
      validationPassed=0
    fi
  else
    colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x 或 Ubuntu 20/22/24 版本 64 位"
    validationPassed=0
  fi
else
  colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x 或 Ubuntu 20/22/24 版本 64 位"
  validationPassed=0
fi

#服务器架构检测
echo -ne "服务器架构检测 \t\t........................ "
is64bitArch=`uname -m`
if [[ "x$is64bitArch" == "xx86_64" ]] || [[ "x$is64bitArch" == "xaarch64" ]];then
   colorMsg $green "[OK]"
else
   colorMsg $red "[ERROR] 架构必须是 x86_64，或者 aarch64"
   validationPassed=0
fi


#CPU检测
echo -ne "CPU检测 \t\t........................ "
processor=`cat /proc/cpuinfo| grep "processor"| wc -l`
if [ $processor -lt 4 ];then
  colorMsg $yellow "[WARNING] CPU 小于 4核，建议 FIT2CLOUD 服务所在机器的 CPU 至少 4 核"
  validationWarning=0
else
  colorMsg $green "[OK]"
fi


#内存检测
echo -ne "内存检测 \t\t........................ "
memTotal=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
if [ $memTotal -lt 16000000 ];then
  colorMsg $yellow "[WARNING] 内存小于 16G，建议 FIT2CLOUD 服务所在机器的内存至少 16G"
  validationWarning=0
else
  colorMsg $green "[OK]"
fi

#磁盘剩余空间检测
echo -ne "磁盘剩余空间检测 \t........................ "
path="$installerPath/fit2cloud"
opt_path="$installerPath"

IFSOld=$IFS
IFS=$'\n'
lines=$(df -P)
for line in ${lines};do
  linePath=`echo ${line} | awk -F' ' '{print $6}'`
  lineAvail=`echo ${line} | awk -F' ' '{print $4}'`
  if [ "${linePath:0:1}" != "/" ]; then
    continue
  fi

  if [ "${linePath}" == "/" ]; then
    rootAvail=${lineAvail}
    continue
  fi

  pathLength=${#path}
  if [ "${linePath:0:${pathLength}}" == "${path}" ]; then
    pathAvail=${lineAvail}
    break
  fi

  opt_pathLength=${#opt_path}
  if [ "${linePath:0:${opt_pathLength}}" == "${opt_path}" ]; then
    opt_pathAvail=${lineAvail}
    break
  fi
done
IFS=$IFSOld

if test -z "${pathAvail}"
then
  if test -z "${opt_pathAvail}"
  then
    pathAvail=${rootAvail}
  else
    pathAvail=${opt_pathAvail}
  fi
fi

if [ $pathAvail -lt 200000000 ]; then
  colorMsg $yellow "[WARNING] 安装目录剩余空间小于 200G，FIT2CLOUD 所在机器的安装目录可用空间需要至少 200G"
  validationWarning=0
else
  colorMsg $green "[OK]"
fi


#docker环境检测
echo -ne "Docker 检测 \t\t........................ "
hasDocker=$(which docker 2>/dev/null)
if [[ -z "$hasDocker" ]]; then
  colorMsg $green '[OK]'
else
  # 获取 Docker 版本
  dockerVersion=$(docker info --format '{{.ServerVersion}}' | awk -F. '{print $1}')
  if [[ -z "$dockerVersion" ]]; then
    colorMsg $red "[ERROR] 无法获取 Docker 版本"
    validationPassed=0
  elif [[ "$dockerVersion" -lt "18" ]]; then
    colorMsg $red "[ERROR] Docker 版本需要 18 以上"
    validationPassed=0
  else
    dockerDir=$(get_docker_dir)
    colorMsg $green "[OK] 存储目录：$dockerDir，请确保目录空间充足"

    echo -ne "docker-compose 检测 \t........................ "
    hasDockerCompose=$(which docker-compose 2>/dev/null)
    if [[ -z "$hasDockerCompose" ]]; then
      colorMsg $red "[ERROR] 未安装 docker-compose"
      validationPassed=0
    else
      colorMsg $green '[OK]'
    fi
  fi
fi


fit2cloudPorts=`grep -A 1 "ports:$" ../fit2cloud/docker-compose.yml | grep "\-.*:" | awk -F":" '{print $1}' | awk -F" " '{print $2}'`
for fit2cloudPort in ${fit2cloudPorts}; do
  checkPort $fit2cloudPort
done

if [ $validationPassed -eq 0 ]; then
  colorMsg $red "\n${systemName} 安装环境检测未通过，请查阅上述环境检测结果\n"
  exit 1
fi

if [ $validationWarning -eq 0 ]; then
  echo -e "\n"
  read -p "${systemName} 安装环境检测异常，机器配置建议不能低于，4C 16G 200G。是否跳过? [y/n](默认y):" skipWarning
  if [ "${skipWarning}" == "n" ];then
    colorMsg $red "\n${systemName} 安装环境检测未通过，请查阅上述环境检测结果\n"
    exit 1
  fi
fi

printTitle "开始进行${systemName} 安装"


# step 1 - install docker & docker-compose
printSubTitle "安装 Docker 运行时环境"
if [[ -z "$hasDocker" ]]; then
  if [ ! -f "$dockerConfigFile" ];then
    echo "修改 docker 存储目录到 $dockerPath"
    if [ ! -d "$dockerPath" ];then
      mkdir -p "$dockerPath"
    fi

    if [ ! -d "$dockerConfigFolder" ];then
      mkdir -p "$dockerConfigFolder"
    fi

cat > $dockerConfigFile <<EOF
{
  "graph": "$dockerPath",
  "hosts": ["unix:///var/run/docker.sock"],
  "log-driver": "json-file",
  "log-opts": {
      "max-size": "124m",
      "max-file": "10"
  }
}
EOF
fi

  chmod -R +x ../fit2cloud/tools/docker/bin/
  if [[ $majorVersion == 7 || -f /etc/kylin-release ]] || [[ $majorVersion == 20 ]] || [[ $majorVersion == 22 ]] || [[ $majorVersion == 24 ]];then
    \cp -p ../fit2cloud/tools/docker/bin/* /usr/bin/
    \cp ../fit2cloud/tools/docker/service/docker.service /etc/systemd/system/
    chmod 754 /etc/systemd/system/docker.service
  elif [[ $majorVersion == 8 ]];then
    docker_install_log="/var/log/docker-install.log"
    rpm -ivh ../fit2cloud/tools/docker-rhel8/libcgroup-0.41-19.el8.x86_64.rpm >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/glibc-2.28-151.el8.i686.rpm >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/libcgroup-0.41-19.el8.i686.rpm >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/docker-ce-cli-20.10.18-3.el8.x86_64.rpm >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/docker-scan-plugin-0.17.0-3.el8.x86_64.rpm >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/containerd.io-1.6.8-3.1.el8.x86_64.rpm --force --nodeps >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/docker-ce-rootless-extras-20.10.18-3.el8.x86_64.rpm --force --nodeps >> $docker_install_log 2>&1
    rpm -ivh ../fit2cloud/tools/docker-rhel8/docker-ce-20.10.18-3.el8.x86_64.rpm --force --nodeps >> $docker_install_log 2>&1
    \cp ../fit2cloud/tools/docker-rhel8/docker-compose /usr/local/bin && sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    # 因为 docker 的 socket 配置出现了冲突，需要删除
    sed -i 's@-H fd:// @@g' /usr/lib/systemd/system/docker.service
  else
    colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x 版本 64 位, Ubuntu 20/22/24"
  fi

  echo -ne "Docker \t\t\t........................ "
  colorMsg $green "[OK] 存储目录：$dockerPath"
else
  echo -ne "Docker \t\t\t........................ "
  colorMsg $green "[OK] 已存在 Docker 运行时环境，忽略安装"
fi
systemctl daemon-reload >> $installLog 2>&1
systemctl start docker  >> $installLog 2>&1
systemctl enable docker >> $installLog 2>&1
echo -ne "启动 Docker 服务 \t........................ "
colorMsg $green "[OK]"

if [ `grep "vm.max_map_count" /etc/sysctl.conf | wc -l` -eq 0 ];then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  sysctl -p /etc/sysctl.conf >> $installLog
fi


# step 2 - load fit2cloud 2.0 docker images
echo
printSubTitle "加载 Docker 镜像"
docker_images_folder="../docker-images"
systemctl restart docker
for docker_image in ${docker_images_folder}/*; do
  temp_file=`basename $docker_image`
  printf "加载镜像 %-45s ........................ " $temp_file
  docker load -q -i ${docker_images_folder}/$temp_file >> $installLog
  printf "\e[32m[OK]\e[0m \n"
done


# step 3 - config fit2cloud service
printTitle "配置 FIT2CLOUD 服务"
#开放端口
open_port 80
# open_port 2375
open_port 8211

echo -ne "配置 FIT2CLOUD 服务 \t\t........................ "
cp -rp ../fit2cloud $installerPath
rm -rf $installerPath/fit2cloud/bin/fit2cloud
chmod -R 777 $installerPath/fit2cloud/data
chmod -R 777 $installerPath/fit2cloud/git
chmod -R 777 $installerPath/fit2cloud/sftp
chmod -R 777 $installerPath/fit2cloud/conf/rabbitmq
chmod -R 777 $installerPath/fit2cloud/logs/rabbitmq
chmod 644 $installerPath/fit2cloud/conf/my.cnf
\cp fit2cloud.service /etc/init.d/fit2cloud
chmod a+x /etc/init.d/fit2cloud
\cp f2cctl /usr/bin/f2cctl
chmod a+x /usr/bin/f2cctl

if [[ $majorVersion == 7 || -f /etc/kylin-release ]]; then
    chkconfig --add fit2cloud
    fit2cloudService=$(grep "service fit2cloud start" /etc/rc.d/rc.local | wc -l)
    if [[ "$fit2cloudService" -eq 0 ]]; then
        echo "sleep 10" >> /etc/rc.d/rc.local
        echo "service fit2cloud start" >> /etc/rc.d/rc.local
    fi
    chmod +x /etc/rc.d/rc.local
elif [[ $majorVersion == 20 || $majorVersion == 22 || $majorVersion == 24 ]]; then
    if [[ -f /etc/init.d/fit2cloud ]]; then
        chmod +x /etc/init.d/fit2cloud
    else
        echo "Error: /etc/init.d/fit2cloud script not found."
        exit 1
    fi
fi

systemctl restart docker
colorMsg $green "[OK]"

#根据用户输入决定是否安装MinIO
if $install_minio ;then
  open_port ${port}

  cd ../fit2cloud/tools/minio/
  sh minio-install.sh -d $folder -p $port
fi

# step 4 - config fit2cloud cmp address
echo -ne "配置云管服务器的访问地址 \t........................ "
#查询结果转成数组
nums=($ips)

if [ ${#nums[@]} -gt 1 ]; then
  #有多个网卡ip
  echo -e "存在多网卡IP："

  for i in ${nums[@]}
  do
    echo -e "               $i"
  done

  read -p "将自动设置云管访问地址为：${nums[0]} ；修改？（y/n）" beSure

  if [ "${beSure}" == "y" ];then
    read -p "请输入云管访问地址，按enter确认：" ipAddr

    if [[ $ipAddr == https://* ]]; then
      ipAddr=${ipAddr: 8}
    fi
    if [[ $ipAddr == http://* ]]; then
      ipAddr=${ipAddr: 7}
    fi

    #如果未输入则取第一个
    if [ -z "$ipAddr" ]; then
      ipAddr=${nums[0]}
    fi
  else
    #如果未输入则取第一个
    ipAddr=${nums[0]}
  fi

  echo "云管访问地址为：http://$ipAddr"
  echo "#云管访问地址" >> $installerPath/fit2cloud/conf/fit2cloud.properties
  echo "fit2cloud.cmp.address=http://$ipAddr" >> $installerPath/fit2cloud/conf/fit2cloud.properties
elif [ ${#nums[@]} = 1 ]; then
  #只有一个网卡ip
  ipAddr=${nums[0]}
  echo "    http://${nums[0]}"
  echo "#云管访问地址" >> $installerPath/fit2cloud/conf/fit2cloud.properties
  echo "fit2cloud.cmp.address=http://${nums[0]}" >> $installerPath/fit2cloud/conf/fit2cloud.properties
else
  #没有网卡ip
  echo "没有查询到网卡IP，请输入一个云管访问地址的IP或域名，默认为空。"
  read -p "之后可手动在【管理中心-系统设置-系统参数】维护，按enter确认：" ipAddr

  if [[ $ipAddr == https://* ]]; then
    ipAddr=${ipAddr: 8}
  fi
  if [[ $ipAddr == http://* ]]; then
    ipAddr=${ipAddr: 7}
  fi

  if [ -n "$ipAddr" ]; then
    echo "    http://$ipAddr"
  fi
  echo "#云管访问地址" >> $installerPath/fit2cloud/conf/fit2cloud.properties
  echo "fit2cloud.cmp.address=http://$ipAddr" >> $installerPath/fit2cloud/conf/fit2cloud.properties
fi

# 数据采集配置文件需要配置当前宿主机真实IP
# sed -i s@tcp://localip:2375@tcp://$ipAddr:2375@g $installerPath/fit2cloud/conf/telegraf.conf
echo "配置已写入，可在【管理中心-系统设置-系统参数】中搜索 fit2cloud.cmp.address 进行管理.
配置云管服务器的访问地址结束."

# step 5 - start fit2cloud
printTitle "启动 FIT2CLOUD 服务"
echo -ne "启动 FIT2CLOUD 服务 \t........................ "
if [[ $majorVersion == 7 || -f /etc/kylin-release ]]; then
  service fit2cloud start >> $installLog 2>&1
  colorMsg $green "[OK]"
elif [[ $majorVersion == 20 || $majorVersion == 22 || $majorVersion == 24 ]]; then
  /etc/init.d/fit2cloud start >> $installLog 2>&1
  colorMsg $green "[OK]"
  colorMsg $yellow "[Warning] 此操作系统为$ID,请使用/etc/init.d/fit2cloud [status | start | stop] 来进行服务管理"
else
  colorMsg $red "[ERROR] 未找到此操作系统的启动命令, 请手动重启"
fi

if [ -d ../../../extensions/ ];then
  cd ../../../extensions/
  extensions=($(ls))
  sleep 60
  echo -e "安装扩展模块 \t\t........................ "
  while 'true';do
    startingNum=$(service fit2cloud status | grep starting | wc -l)
    if [ "$startingNum" -eq 0 ];then
      for i in ${extensions[@]} ; do
        read -p "是否安装扩展模块 ${i}? [y/n](默认n):" word
        if echo "$word" | grep -qwi "y";then
            /bin/f2cctl install-module $i
        fi
      done
      break
    else
      sleep 10
    fi
  done
fi

# by <Jinli - 20240704> install telegraf
# 非欧拉系统安装telegraf-install
if [ "$ID" != "openEuler" ]; then
    # 检查安装脚本是否存在
    if [ ! -f "$installerPath/fit2cloud/tools/telegraf/telegraf-install.sh" ]; then
        echo "错误：telegraf-install 脚本未找到，跳过安装！"
    else
        # 执行安装脚本
        bash "$installerPath/fit2cloud/tools/telegraf/telegraf-install.sh"
    fi

fi

echo
echo "*********************************************************************************************************************************"
echo -e "\t${systemName} 安装完成，请在服务完全启动后(大概需要等待5分钟左右)访问 http://${ipAddr} 来访问 FIT2CLOUD 云管平台"
echo
echo -e "\t系统管理员初始登录信息："
echo -ne "\t    用户名："
colorMsg $yellow "\tadmin"
echo -ne "\t    密码："
colorMsg $yellow "\tPassword123@cmp"
echo "*********************************************************************************************************************************"
echo