#!/bin/bash

installerPath=/opt
container_name="influxdb"

# 最大等待时间（秒）
max_wait_time=120
wait_interval=5
elapsed_time=0

# 检查容器健康状态的函数
check_health() {
  health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name")
  echo "$health_status"
}
echo "**********	 部署 Telegraf 组件 	**********"
echo ""
# 等待容器健康
while [ "$elapsed_time" -lt "$max_wait_time" ]; do
  health_status=$(check_health)
  if [ "$health_status" == "healthy" ]; then
    echo "## 开始部署 Telegraf，大约需等待一分钟 ..."
    file_path="$installerPath/fit2cloud/tools/telegraf/telegraf-1.24.4-1.x86_64.rpm"
    if [ -f "$file_path" ]; then
        cd $installerPath/fit2cloud/tools/telegraf/
        rpm -ivh $installerPath/fit2cloud/tools/telegraf/telegraf-1.24.4-1.x86_64.rpm
        \cp $installerPath/fit2cloud/conf/telegraf.conf /etc/telegraf/
        echo "## 开始启动 Telegraf 并添加到自启服务 ..."
        systemctl start telegraf
        systemctl enable telegraf
        status=$(systemctl is-active telegraf)
        if [ "$status" != "active" ]; then
            echo "## Telegraf 服务启动失败，检查后手动重启 ..."
        else
            echo "## Telegraf 服务启动成功 ..."
        fi
    else
    echo "## 安装包 $file_path 不存在,手动检查安装"
    fi

    # 例如：./install.sh
    exit 0
  fi
  sleep "$wait_interval"
  elapsed_time=$((elapsed_time + wait_interval))
done

# 超过最大等待时间仍不健康
echo "安装失败：依赖容器 $container_name未启动，请检查后手动部署。"