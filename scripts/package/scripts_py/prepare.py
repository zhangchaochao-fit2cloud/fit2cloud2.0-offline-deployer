#!/usr/bin/env python3
"""
准备安装包文件 — 对应 prepare.sh。

执行：
1. 复制 extensions 到 installer_dir
2. 复制 opt 目录内容
3. 生成 .env
4. 解压 aws_price.json.zip
5. 清理运行时残留
6. 复制 scripts_py（如果启用）
"""

import os
import sys
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from logger import (
    log_info, log_warn, log_success, print_title,
)


def ensure_dir(path):
    """确保目录存在。"""
    Path(path).mkdir(parents=True, exist_ok=True)


def copy_extensions(base_dir, installer_dir):
    """复制 extensions 目录。"""
    ext_src = base_dir / "extensions"
    if ext_src.exists():
        ext_dst = installer_dir / "extensions"
        shutil.copytree(str(ext_src), str(ext_dst))
        log_info("扩展文件复制完成")


def copy_opt(base_dir, installer_dir):
    """复制 opt 目录内容到 installer 根。"""
    opt_src = base_dir / "opt" / "fit2cloud"
    if opt_src.exists():
        for item in opt_src.iterdir():
            dst = installer_dir / item.name
            if dst.exists():
                if dst.is_dir():
                    shutil.rmtree(str(dst), ignore_errors=True)
                else:
                    dst.unlink()
            shutil.copytree(str(item), str(dst)) if item.is_dir() else shutil.copy2(str(item), str(dst))
        log_info("opt 文件复制完成")


def generate_env(installer_dir, registry_url, version, platform):
    """生成 .env 文件。"""
    env_path = installer_dir / "fit2cloud" / ".env"
    ensure_dir(env_path.parent)
    with open(env_path, "w") as f:
        f.write(f"IMAGE_ADDRESS={registry_url}/north\n")
        f.write(f"VERSION={version}\n")
        f.write(f"PLATFORM={platform}\n")
    log_info(".env 已生成（仅含 IMAGE_ADDRESS/VERSION/PLATFORM）")


def unzip_aws_price(installer_dir):
    """解压 aws_price.json.zip。"""
    zip_path = installer_dir / "fit2cloud" / "conf" / "aws_price.json.zip"
    if zip_path.exists():
        conf_dir = installer_dir / "fit2cloud" / "conf"
        result = subprocess.run(
            ["unzip", "-o", str(zip_path), "-d", str(conf_dir)],
            capture_output=True, timeout=30
        )
        if result.returncode == 0:
            log_info("AWS 询价 JSON 解压完成")


def clean_runtime(installer_dir):
    """清理运行时残留。"""
    clean_paths = [
        installer_dir / "fit2cloud" / "data" / "mysql",
        installer_dir / "fit2cloud" / "data" / "minio" / ".minio.sys",
        installer_dir / "fit2cloud" / "logs",
    ]
    for p in clean_paths:
        if p.exists():
            if p.is_dir():
                shutil.rmtree(str(p), ignore_errors=True)
            else:
                p.unlink()

    # 删除配置文件
    for f in ["install.env", "runtime.env"]:
        fp = installer_dir / "fit2cloud" / f
        if fp.exists():
            fp.unlink()

    # 删除 .DS_Store
    find_result = subprocess.run(
        ["find", str(installer_dir), "-name", ".DS_Store", "-delete"],
        capture_output=True, timeout=30
    )
    # ignore errors


def copy_scripts_py(base_dir, installer_dir, version, build_number):
    """复制 Python 实验版本脚本。"""
    scripts_py_src = base_dir / "opt" / "fit2cloud" / "scripts_py"
    if scripts_py_src.exists():
        scripts_py_dst = installer_dir / "fit2cloud" / "scripts_py"
        if scripts_py_dst.exists():
            shutil.rmtree(str(scripts_py_dst), ignore_errors=True)
        shutil.copytree(str(scripts_py_src), str(scripts_py_dst))

        # 写版本标记
        version_file = scripts_py_dst / ".version"
        with open(version_file, "w") as f:
            f.write(f"enabled=true\n")
            f.write(f"build_version={version}.{build_number}\n")
            f.write(f"build_time={datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        log_info("Python 实验版本已包含（scripts_py/）")
    else:
        log_warn("scripts_py/ 目录不存在，跳过 Python 版本打包")


def prepare(output_dir, installer_dir, base_dir, version="2.0", build_number="1",
            registry_url="registry.fit2cloud.com/north", platform="amd64",
            with_python=False):
    """准备安装包文件。

    Args:
        output_dir: 输出目录
        installer_dir: 安装包目录
        base_dir: 项目根目录
        version: 版本号
        build_number: 构建号
        registry_url: 镜像仓库地址
        platform: 目标平台
        with_python: 是否包含 Python 版本
    """
    print_title("步骤 1/5: 准备安装包文件")

    base = Path(base_dir)
    installer = Path(installer_dir)
    output = Path(output_dir)

    ensure_dir(installer)

    # 清理输出目录
    shutil.rmtree(str(output), ignore_errors=True)
    shutil.rmtree(str(installer), ignore_errors=True)
    ensure_dir(installer)

    copy_extensions(base, installer)
    copy_opt(base, installer)
    generate_env(installer, registry_url, version, platform)
    unzip_aws_price(installer)
    clean_runtime(installer)

    if with_python:
        copy_scripts_py(base, installer, version, build_number)

    log_success("安装包文件准备完成")
