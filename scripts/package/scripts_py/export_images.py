#!/usr/bin/env python3
"""
镜像导出模块 — 对应 export-images.sh + docker.sh::export_docker_images。

将本地 Docker 镜像导出为单文件 tar。
"""

import os
import sys
import subprocess
import json
from pathlib import Path

from logger import (
    print_title, print_subtitle, log_info, log_success,
    log_error, log_warn, log_info_inline, log_step_success,
)


def get_all_images(env_file):
    """从 docker compose 配置中获取所有镜像名。"""
    result = subprocess.run(
        ["docker", "compose", "version"],
        capture_output=True, timeout=5
    )
    compose_cmd = "docker compose"
    if result.returncode != 0:
        if subprocess.run(["which", "docker-compose"], capture_output=True).returncode == 0:
            compose_cmd = "docker-compose"
        else:
            return []

    result = subprocess.run(
        compose_cmd.split() + ["config"],
        capture_output=True, text=True, timeout=30,
        cwd=str(Path(env_file).parent)
    )
    if result.returncode != 0:
        return []

    images = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("image:"):
            parts = line.split(None, 1)
            if len(parts) >= 2:
                img = parts[1].strip('"')
                if img:
                    images.append(img)
    return images


def verify_image_arch(image_name, expected_platform):
    """验证镜像架构。"""
    result = subprocess.run(
        ["docker", "inspect", "--format={{.Architecture}}", image_name],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode != 0:
        return
    arch = result.stdout.strip()
    if arch and arch != expected_platform:
        log_warn(f"镜像 {image_name} 架构为 {arch}, 期望 {expected_platform}")


def export_docker_images(images_dir, env_file, dry_run=False):
    """导出 Docker 镜像为单文件 tar。"""
    print_subtitle("导出 Docker 镜像...")

    if not images_dir:
        log_warn("没有指定 Docker 导出目录")
        return

    Path(images_dir).mkdir(parents=True, exist_ok=True)

    image_list = get_all_images(env_file)
    total = len(image_list)

    if total == 0:
        log_error("未解析到任何镜像，无法导出")
        return 1

    # 前置校验
    missing = 0
    for image_name in image_list:
        result = subprocess.run(
            ["docker", "image", "inspect", image_name],
            capture_output=True, timeout=10
        )
        if result.returncode != 0:
            log_error(f"镜像不存在于本地: {image_name}")
            missing += 1

    if missing > 0:
        return 1

    if dry_run:
        log_info(f"将导出 {total} 个镜像为单文件 {images_dir}/fit2cloud-images.tar（dry-run 跳过）")
        return 0

    output_tar = os.path.join(images_dir, "fit2cloud-images.tar")
    result = subprocess.run(
        ["docker", "save", "-o", output_tar] + image_list,
        capture_output=True, text=True, timeout=3600
    )
    if result.returncode != 0:
        log_error(f"docker save 失败: {result.stderr[:200]}")
        return 1

    with open(os.path.join(images_dir, "images.list"), "w") as f:
        for name in image_list:
            f.write(name + "\n")

    log_success(f"镜像导出完成: fit2cloud-images.tar（共 {total} 个镜像）")
    return 0


def export_images(images_dir, env_file, report_file, dry_run=False):
    """导出镜像入口。"""
    print_title("步骤 3/5: 导出 Docker 镜像")

    export_docker_images(images_dir, env_file, dry_run)

    # 统计 tar 文件数
    total_files = 0
    if Path(images_dir).exists():
        total_files = len(list(Path(images_dir).glob("*.tar")))

    if report_file:
        os.makedirs(os.path.dirname(os.path.abspath(report_file)), exist_ok=True)
        with open(report_file, "w") as f:
            json.dump({
                "total": total_files,
                "output_dir": images_dir,
            }, f, indent=2)

    log_success(f"镜像导出完成: {total_files} 个文件")
