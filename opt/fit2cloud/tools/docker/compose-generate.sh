#!/bin/bash
# 动态生成 docker-compose -f 参数组合
# 用法：source 本脚本后，使用 $COMPOSE_FILES 变量

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR"

# 默认主 compose 文件
COMPOSE_FILES="$COMPOSE_DIR/../../external-compose/base-docker-compose.yml"

# 判断是否需要本地 mysql
if [[ -z "$MYSQL_HOST" ]]; then
  COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_DIR/mysql-docker-compose.yml"
fi

# 判断是否需要本地 redis
if [[ -z "$REDIS_HOST" ]]; then
  COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_DIR/redis-docker-compose.yml"
fi

# 判断是否需要本地 influxdb
if [[ -z "$INFLUXDB_HOST" ]]; then
  COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_DIR/influxdb-docker-compose.yml"
fi

# 判断是否需要本地 rabbitmq
if [[ -z "$RABBITMQ_HOST" ]]; then
  COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_DIR/rabbitmq-docker-compose.yml"
fi

# 允许外部脚本 source 后直接用 $COMPOSE_FILES
export COMPOSE_FILES

# 也可直接输出
if [[ "$1" == "print" ]]; then
  echo "$COMPOSE_FILES"
fi 