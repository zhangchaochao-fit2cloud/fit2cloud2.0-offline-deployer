#docker环境检测
echo -ne "Docker 检测 \t\t........................ "
hasDocker=`which docker 2>&1`
if [[ "${hasDocker}" =~ "no docker" ]]; then
  echo '未安装'
else
  dockerVersion=`docker info | grep 'Server Version' | awk -F: '{print $2}' | awk -F. '{print $1}'`
  if [ "$dockerVersion" -lt "18" ];then
    echo "[ERROR] Docker 版本需要 18 以上"
    exit 1
  else
    echo "已安装"

    echo -ne "docker-compose 检测 \t........................ "
    hasDockerCompose=`which docker-compose 2>&1`
    if [[ "${hasDockerCompose}" =~ "no docker-compose" ]]; then
      echo "[ERROR] 未安装 docker-compose"
      exit 1
    else
      echo '已安装'
      echo "已存在 Docker 运行时环境，忽略安装" 
      exit 0
    fi
  fi
fi

dockerPath="/opt/fit2cloud/docker"
dockerConfigFolder="/etc/docker"
dockerConfigFile="$dockerConfigFolder/daemon.json"

if [ ! -d "$dockerPath" ];then
  mkdir -p "$dockerPath"
fi

if [ ! -d "$dockerConfigFolder" ];then
  mkdir -p "$dockerConfigFolder"
fi

echo "开始安装 Docker 运行时环境"
if [[ "${hasDocker}" =~ "no docker" ]]; then
  echo "修改 docker 存储目录到 $dockerPath"
  cat <<EOF> $dockerConfigFile
  {
    "graph": "$dockerPath",
    "data-root": "$dockerPath",
    "log-driver": "json-file",
      "log-opts": {
        "max-size": "10m",    // 单个日志文件最大大小
        "max-file": "3",      // 保留的日志文件最大数量
      }
  }
EOF

  chmod -R +x docker/bin/
  cp -p docker/bin/* /usr/bin/
  cp docker/service/docker.service /etc/systemd/system/
  chmod 754 /etc/systemd/system/docker.service
  echo -e "Docker 安装 ........................ [OK]"
else
  echo "已存在 Docker 运行时环境，忽略安装" 
  exit 0
fi
systemctl start docker
systemctl enable docker
echo -e "启动 Docker 服务 \t........................ [OK]"