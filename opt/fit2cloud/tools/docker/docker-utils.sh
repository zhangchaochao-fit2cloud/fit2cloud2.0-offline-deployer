#!/bin/bash
# docker 相关通用函数

log_info() {
  echo -e "\033[32m[INFO]\033[0m $1"
}

log_error() {
  echo -e "\033[31m[ERROR]\033[0m $1"
}

# 检查 Docker 是否安装
docker_check() {
  if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装，请先安装 Docker"
    return 1
  fi
  local docker_version=$(docker info | grep 'Server Version' | awk -F: '{print $2}' | awk -F. '{print $1}')
  if [[ "$docker_version" -lt "18" ]]; then
    log_error "Docker 版本需要 18 以上，当前版本: $docker_version"
    return 1
  fi
  log_info "Docker 版本检查通过: $docker_version"
  return 0
}

# 检查 docker-compose 是否安装
docker_compose_check() {
  if ! command -v docker-compose &> /dev/null; then
    log_error "docker-compose 未安装，请先安装 docker-compose"
    return 1
  fi
  log_info "docker-compose 检查通过"
  return 0
}

# 启动 Docker 服务
docker_start() {
  if systemctl is-active --quiet docker; then
    log_info "Docker 服务已在运行"
  else
    systemctl start docker
    systemctl enable docker
    log_info "Docker 服务启动完成"
  fi
}

# 统一导出
export -f log_info log_error docker_check docker_compose_check docker_start 