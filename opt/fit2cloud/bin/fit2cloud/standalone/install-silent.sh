#!/bin/bash
#提示用户是否需要安装文件服务器minio
install_minio=true
minio_port_valid=false

installerPath=$(pwd)
installLog="/tmp/fit2cloud-install.log"
dockerPath="/opt/fit2cloud/docker"
dockerConfigFolder="/etc/docker"
dockerConfigFile="$dockerConfigFolder/daemon.json"
# ips=`ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:"`
ips=`ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p'`

red=31
green=32
yellow=33
blue=34
validationPassed=1

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

# 静默安装minio仓库
echo "使用默认安装路径/opt/fit2cloud"
folder="/opt/fit2cloud"
port=9001
echo "检测$port端口是否被占用"
checkMinIOPort $port
echo "使用默认端口9001"

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
if [ -f /etc/redhat-release ];then
  osVersion=`cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+'`
  majorVersion=`echo $osVersion | awk -F. '{print $1}'`
  minorVersion=`echo $osVersion | awk -F. '{print $2}'`
  if [ "x$majorVersion" == "x" ];then
    colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x 版本 64 位"
    validationPassed=0
  else
    if [[ $majorVersion == 7 ]] || [[ $majorVersion == 8 ]];then
      is64bitArch=`uname -m`
      if [[ "x$is64bitArch" == "xx86_64" ]] || [[ "x$is64bitArch" == "xaarch64" ]];then
         colorMsg $green "[OK]"
      else
         colorMsg $red "[ERROR] 操作系统必须是 64 位的，32 位的不支持"
         validationPassed=0
      fi
    else
      colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x 版本 64 位"
      validationPassed=0
    fi
  fi
else
    colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x, RHEL 7.x 版本 64 位"
    validationPassed=0
fi


#CPU检测
echo -ne "CPU检测 \t\t........................ "
processor=`cat /proc/cpuinfo| grep "processor"| wc -l`
if [ $processor -lt 4 ];then
  colorMsg $red "[ERROR] CPU 小于 4核，FIT2CLOUD 所在机器的 CPU 需要至少 4核"
  validationPassed=0
else
  colorMsg $green "[OK]"
fi


#内存检测
echo -ne "内存检测 \t\t........................ "
memTotal=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
if [ $memTotal -lt 16000000 ];then
  colorMsg $red "[ERROR] 内存小于 16G，FIT2CLOUD 所在机器的内存需要至少 16G"
  validationPassed=0
else
  colorMsg $green "[OK]"
fi


#磁盘剩余空间检测
echo -ne "磁盘剩余空间检测 \t........................ "
path="/opt/fit2cloud"
opt_path="/opt"

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
  colorMsg $red "[ERROR] 安装目录剩余空间小于 200G，FIT2CLOUD 所在机器的安装目录可用空间需要至少 200G"
  validationPassed=0
else
  colorMsg $green "[OK]"
fi


#docker环境检测
echo -ne "Docker 检测 \t\t........................ "
hasDocker=`which docker 2>&1`
if [[ "${hasDocker}" =~ "no docker" ]]; then
  colorMsg $green '[OK]'
else
  dockerVersion=`docker info | grep 'Server Version' | awk -F: '{print $2}' | awk -F. '{print $1}'`
  if [ "$dockerVersion" -lt "18" ];then
    colorMsg $red "[ERROR] Docker 版本需要 18 以上"
    validationPassed=0
  else
    colorMsg $green "[OK]"

    echo -ne "docker-compose 检测 \t........................ "
    hasDockerCompose=`which docker-compose 2>&1`
    if [[ "${hasDockerCompose}" =~ "no docker-compose" ]]; then
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

printTitle "开始进行${systemName} 安装"


# step 1 - install docker & docker-compose
printSubTitle "安装 Docker 运行时环境"
if [[ "${hasDocker}" =~ "no docker" ]]; then

  if [ ! -f "$dockerConfigFile" ];then
    echo "修改 docker 存储目录到 $dockerPath"

    if [ ! -d "$dockerPath" ];then
      mkdir -p "$dockerPath"
    fi

    if [ ! -d "$dockerConfigFolder" ];then
      mkdir -p "$dockerConfigFolder"
    fi

    cat <<EOF> $dockerConfigFile
    {
      "graph": "$dockerPath",
      "hosts": ["unix:///var/run/docker.sock"]
    }
EOF
  fi

  chmod -R +x ../fit2cloud/tools/docker/bin/
  if [[ $majorVersion == 7 ]];then
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
    mv ../fit2cloud/tools/docker-rhel8/docker-compose /usr/local/bin && sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    # 因为 docker 的 socket 配置出现了冲突，需要删除
    sed -i 's@-H fd:// @@g' /usr/lib/systemd/system/docker.service
    systemctl daemon-reload >> $installLog 2>&1
  else
    colorMsg $red "[ERROR] 操作系统类型版本不符合要求，请使用 CentOS 7.x/8.x, RHEL 7.x/8.x 版本 64 位"
  fi
  echo -ne "Docker \t\t\t........................ "
  colorMsg $green "[OK]"
else
  echo -ne "Docker \t\t\t........................ "
  colorMsg $green "[OK] 已存在 Docker 运行时环境，忽略安装"
fi

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

echo -ne "配置 FIT2CLOUD 服务 \t\t........................ "
cp -rp ../fit2cloud /opt/
rm -rf /opt/fit2cloud/bin/fit2cloud
chmod -R 777 /opt/fit2cloud/data
chmod -R 777 /opt/fit2cloud/sftp
chmod -R 777 /opt/fit2cloud/conf/rabbitmq
chmod -R 777 /opt/fit2cloud/logs/rabbitmq
chmod 644 /opt/fit2cloud/conf/my.cnf
\cp fit2cloud.service /etc/init.d/fit2cloud
chmod a+x /etc/init.d/fit2cloud
\cp f2cctl /usr/bin/f2cctl
chmod a+x /usr/bin/f2cctl
# \cp fit2cloud-install-extension.sh /usr/bin/fit2cloud-install-extension
# chmod a+x /usr/bin/fit2cloud-install-extension
# \cp fit2cloud-upgrade-extension.sh /usr/bin/fit2cloud-upgrade-extension
# chmod a+x /usr/bin/fit2cloud-upgrade-extension
chkconfig --add fit2cloud
fit2cloudService=`grep "service fit2cloud start" /etc/rc.d/rc.local | wc -l`
if [ "$fit2cloudService" -eq 0 ]; then
  echo "sleep 10" >> /etc/rc.d/rc.local
  echo "service fit2cloud start" >> /etc/rc.d/rc.local
fi
chmod +x /etc/rc.d/rc.local

systemctl restart docker
colorMsg $green "[OK]"

#根据用户输入决定是否安装MinIO
if $install_minio ;then
  open_port ${port}
  systemctl restart docker

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
  #如果未输入则取第一个
  ipAddr=${nums[0]}

  echo "云管访问地址为：http://$ipAddr"
  echo "#云管访问地址" >> /opt/fit2cloud/conf/fit2cloud.properties
  echo "fit2cloud.cmp.address=http://$ipAddr" >> /opt/fit2cloud/conf/fit2cloud.properties
elif [ ${#nums[@]} = 1 ]; then
  #只有一个网卡ip
  ipAddr=${nums[0]}
  echo "    http://${nums[0]}"
  echo "#云管访问地址" >> /opt/fit2cloud/conf/fit2cloud.properties
  echo "fit2cloud.cmp.address=http://${nums[0]}" >> /opt/fit2cloud/conf/fit2cloud.properties
else
  #没有网卡ip
  echo "没有查询到网卡IP，请输入一个云管访问地址的IP或域名，默认为空。"
  echo "之后可手动在【管理中心-系统设置-系统参数】维护。"

  if [[ $ipAddr == https://* ]]; then
    ipAddr=${ipAddr: 8}
  fi
  if [[ $ipAddr == http://* ]]; then
    ipAddr=${ipAddr: 7}
  fi

  if [ -n "$ipAddr" ]; then
    echo "    http://$ipAddr"
  fi
  echo "#云管访问地址" >> /opt/fit2cloud/conf/fit2cloud.properties
  echo "fit2cloud.cmp.address=http://$ipAddr" >> /opt/fit2cloud/conf/fit2cloud.properties
fi

echo "配置已写入，可在【管理中心-系统设置-系统参数】中搜索 fit2cloud.cmp.address 进行管理.
配置云管服务器的访问地址结束."

# 数据采集配置文件需要配置当前宿主机真实IP
# sed -i s@tcp://localip:2375@tcp://$ipAddr:2375@g /opt/fit2cloud/conf/telegraf.conf
# step 5 - start fit2cloud
printTitle "启动 FIT2CLOUD 服务"
echo -ne "启动 FIT2CLOUD 服务 \t........................ "
service fit2cloud start >> $installLog 2>&1
colorMsg $green "[OK]"

if [ -d "$installerPath"/../extensions ];then
  cd "$installerPath"/../extensions
  extensions=($(ls))
  sleep 60
  echo -e "安装扩展模块 \t\t........................ "
  while 'true';do
    startingNum=$(service fit2cloud status | grep starting | wc -l)
    if [ "$startingNum" -eq 0 ];then
      for i in ${extensions[@]} ; do
        /bin/f2cctl install-module $i
      done
      break
    else
      sleep 10
    fi
  done
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
