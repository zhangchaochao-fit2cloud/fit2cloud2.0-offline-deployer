#!/usr/bin/env python3
"""
下载工具包 — 对应 download-tools.sh。

执行：
1. 下载 Docker 安装包
2. 可选：拉取 MinIO 镜像
3. 可选：下载 Telegraf 安装包
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

from logger import (
    log_info, log_warn, log_error, log_success,
    log_info_inline, log_step_success,
    print_title,
)


def cmd_exists(cmd):
    return subprocess.run(["which", cmd], capture_output=True, timeout=2).returncode == 0


def download_file(url, dest):
    """下载文件，优先用 curl，回退 wget。"""
    dest_path = Path(dest)
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    if cmd_exists("curl"):
        result = subprocess.run(
            ["curl", "-fSL", "-o", str(dest_path), url],
            capture_output=True, text=True, timeout=600,
        )
        return result.returncode == 0
    elif cmd_exists("wget"):
        result = subprocess.run(
            ["wget", "--no-check-certificate", "-O", str(dest_path), url],
            capture_output=True, text=True, timeout=600,
        )
        return result.returncode == 0
    else:
        log_error("未找到 curl 或 wget，无法下载")
        return False


def download_local_docker(tools_dir, platform):
    """从本地目录复制 Docker 包。"""
    from_docker_local = os.environ.get("FROM_DOCKER_LOCAL_DIR", "")
    if not from_docker_local or not Path(from_docker_local).exists():
        log_error("FROM_DOCKER_LOCAL_DIR 未设置或目录不存在")
        return 1

    if platform == "arm64":
        docker_zip = "docker-arm64.zip"
    else:
        docker_zip = "docker.zip"

    src = Path(from_docker_local) / docker_zip
    dst = Path(tools_dir) / f"docker_{platform}.zip"
    if not src.exists():
        log_error(f"本地 Docker 包不存在: {src}")
        return 1
    shutil.copy2(str(src), str(dst))

    # RHEL8 tarball
    rhel8_src = Path(from_docker_local) / "docker-rhel8.tar.gz"
    if rhel8_src.exists():
        shutil.copy2(str(rhel8_src), str(Path(tools_dir) / "docker-rhel8.tar.gz"))

    return 0


def download_remote_docker(tools_dir, platform, url_amd64, url_arm64, url_rhel8):
    """从远程下载 Docker 包。"""
    target_url = url_arm64 if platform == "arm64" else url_amd64
    docker_package = f"docker_{platform}.zip"

    download_file(target_url, str(Path(tools_dir) / docker_package))
    download_file(url_rhel8, str(Path(tools_dir) / "docker-rhel8.tar.gz"))

    # 解压
    import zipfile
    zip_path = Path(tools_dir) / docker_package
    with zipfile.ZipFile(str(zip_path), 'r') as z:
        z.extractall(str(Path(tools_dir)))
    zip_path.unlink()

    # 清理 macOS 元数据
    macosx = Path(tools_dir) / "__MACOSX"
    if macosx.exists():
        shutil.rmtree(str(macosx), ignore_errors=True)

    return 0


def download_docker(tools_dir, env_file="", dry_run=False):
    """下载 Docker 安装包。

    对应 bash download_docker()。
    """
    platform = os.environ.get("PLATFORM", "amd64")
    docker_package = f"docker_{platform}.zip"
    tools_path = Path(tools_dir)
    tools_path.mkdir(parents=True, exist_ok=True)

    if dry_run:
        log_info_inline("下载 Docker 安装包")
        log_step_success("跳过")
        return 0

    log_info("下载 Docker 安装包...")

    # 检查本地优先
    from_local = os.environ.get("FROM_DOCKER_LOCAL_DIR", "")
    if from_local and Path(from_local).exists():
        download_local_docker(str(tools_path), platform)
    else:
        # 从环境变量或默认值获取 URL
        url_amd64 = os.environ.get(
            "DOCKER_PACKAGE_URL",
            "https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker.zip"
        )
        url_arm64 = os.environ.get(
            "DOCKER_PACKAGE_URL_ARM64",
            "https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker-arm64.zip"
        )
        url_rhel8 = os.environ.get(
            "DOCKER_PACKAGE_URL_RHEL8",
            "https://f2c-north-rel-1251506367.cos.ap-beijing.myqcloud.com/docker-images/docker-rhel8.tar.gz"
        )
        download_remote_docker(str(tools_path), platform, url_amd64, url_arm64, url_rhel8)

    log_ok()
    return 0


def download_tools(tools_dir, dry_run=False):
    """下载工具包主入口。

    Args:
        tools_dir: 工具目录路径
        dry_run: 是否跳过实际下载
    """
    print_title("步骤 4/5: 下载工具包")

    platform = os.environ.get("PLATFORM", "amd64")

    # Docker 包
    download_docker(str(Path(tools_dir) / "docker"), dry_run=dry_run)

    # MinIO 镜像（可选）
    minio_image = os.environ.get("MINIO_DOCKER_IMAGE", "")
    if minio_image:
        log_info(f"拉取 MinIO 镜像: {minio_image}")
        if not dry_run:
            subprocess.run(
                ["docker", "pull", f"--platform=linux/{platform}", minio_image],
                capture_output=True, timeout=600,
            )
            minio_dir = Path(tools_dir) / "minio"
            minio_dir.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                ["docker", "save", "-o", str(minio_dir / "minio.tar"), minio_image],
                capture_output=True, timeout=300,
            )
            log_info("MinIO 镜像已保存")

    # Telegraf 包（可选）
    telegraf_url = os.environ.get("TELEGRAF_PACKAGE_URL", "")
    if telegraf_url:
        log_info("下载 Telegraf 安装包...")
        if not dry_run:
            telegraf_dir = Path(tools_dir) / "telegraf"
            telegraf_dir.mkdir(parents=True, exist_ok=True)
            download_file(telegraf_url, str(telegraf_dir / "telegraf.rpm"))

    log_success("工具包下载完成")
