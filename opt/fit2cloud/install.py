#!/usr/bin/env python3
"""
install.py — parallel Python version of install.sh

This is the EXPERIMENTAL Python entry point, parallel to bash install.sh.
It does NOT replace the bash version.

Usage:
    python3 install.py --silent
    python3 install.py --dir /opt --env install.env --runtime-env runtime.env
"""

import sys
import os
import argparse
import subprocess
import socket
import time
import hashlib
import re
from pathlib import Path

# Add parent directory to path for local imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts_py.logger import (
    log_info, log_info_inline, log_warn, log_error, log_ok,
    log_step_success, print_title, print_subtitle,
)
from scripts_py.env import (
    read_env_file, get_env_value, set_env_value,
    merge_env_files, load_env,
)
from scripts_py import middleware, docker


def parse_args():
    parser = argparse.ArgumentParser(description="Fit2Cloud 2.0 Offline Installer (Python)")
    parser.add_argument("-s", "--silent", action="store_true",
                        help="Silent mode (no interactive prompts)")
    parser.add_argument("-d", "--dir", type=str,
                        help="Install directory (default: from install.env)")
    parser.add_argument("-e", "--env", type=str, default="install.env",
                        help="Install-time environment file (default: install.env)")
    parser.add_argument("-r", "--runtime-env", type=str, default="runtime.env",
                        help="Runtime environment file (default: runtime.env)")
    parser.add_argument("--no-minio", action="store_true",
                        help="Skip MinIO installation")
    parser.add_argument("--with-nginx", action="store_true",
                        help="Install Nginx")
    parser.add_argument("--force-reinstall", action="store_true",
                        help="Force reinstall")
    parser.add_argument("--verify-images", action="store_true",
                        help="Verify Docker images")
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Step tracking (mirrors run_step / mark_step_done / rollback in bash)
# ---------------------------------------------------------------------------

_current_step = 0
_done_steps = set()


def run_step(step_name: str) -> bool:
    """Start tracking a step. Returns True if already done."""
    global _current_step
    _current_step = step_name
    if step_name in _done_steps:
        return True
    return False


def mark_step_done(step_name: str) -> None:
    _done_steps.add(step_name)


def rollback(step_name: str) -> None:
    """Rollback to previous step on error."""
    log_error(f"回退到: {step_name}")


# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------

def prepare_runtime_secrets(env_file: str) -> None:
    """Prepare runtime secrets in runtime.env (mirrors bash prepare_runtime_secrets)."""
    runtime = Path(env_file)
    if runtime.exists():
        data = read_env_file(str(runtime))
    else:
        data = {}

    # Generate secrets if not already set
    keys_to_generate = [
        "CE_KEYCLOAK_ADMIN_PASSWORD",
        "CE_MYSQL_ROOT_PASSWORD",
        "CE_MYSQL_PASSWORD",
        "CE_MINIO_SECRET_KEY",
    ]
    for key in keys_to_generate:
        if key not in data or not data.get(key):
            data[key] = hashlib.sha256(str(time.time()).encode()).hexdigest()[:16]

    # Write back
    with open(runtime, "w", encoding="utf-8") as f:
        for key, value in data.items():
            f.write(f"{key}={value}\n")


def wait_for_healthy(url: str, timeout: int = 300) -> bool:
    """Wait for a health endpoint to become available."""
    log_info(f"等待服务就绪: {url}")
    start = time.time()
    while time.time() - start < timeout:
        try:
            if docker._check_url(url, timeout=3):
                log_ok()
                return True
        except Exception:
            pass
        time.sleep(5)
    log_error(f"服务未在 {timeout}s 内就绪")
    return False


# ---------------------------------------------------------------------------
# Main installation flow (mirrors install.sh sequence)
# ---------------------------------------------------------------------------

def main():
    args = parse_args()

    ENV_FILE = args.env
    RUNTIME_ENV = args.runtime_env
    SILENT_MODE = args.silent

    print_title("Fit2Cloud 2.0 Offline Installer (Python)")
    print_subtitle("实验性 Python 版本 — 不作为生产使用")

    # --- Step 1: Check Environment ---
    if not run_step("check_environment"):
        log_info_inline("验证环境")
        if not check_environment(args):
            log_error("环境检查失败")
            sys.exit(1)
        mark_step_done("check_environment")

    # --- Step 2: Install Docker ---
    if not run_step("install_docker"):
        log_info_inline("安装 Docker")
        docker.install_docker(args)
        mark_step_done("install_docker")

    # --- Step 3: Prepare Directories ---
    if not run_step("prepare_dir"):
        log_info_inline("准备目录")
        install_path = args.dir or get_env_value("CE_INSTALL_PATH", "/opt", ENV_FILE)
        ensure_dirs(install_path)
        mark_step_done("prepare_dir")

    # --- Step 4: Copy Files ---
    if not run_step("copy_files"):
        log_info_inline("复制文件")
        # TODO: copy required files from offline package
        mark_step_done("copy_files")

    # --- Step 5: Load Images ---
    if not run_step("load_images"):
        log_info_inline("加载镜像")
        docker.load_images(ENV_FILE)
        mark_step_done("load_images")

    # --- Step 6: Render Config ---
    if not run_step("render_config"):
        log_info_inline("渲染配置")
        render_config(ENV_FILE, RUNTIME_ENV)
        mark_step_done("render_config")

    # --- Step 7: Middleware ---
    if not run_step("middleware"):
        log_info_inline("安装中间件")
        engine = middleware.MiddlewareEngine(ENV_FILE)
        # Check phase
        checks = [
            ("MySQL", engine.check_mysql),
            ("Redis", engine.check_redis),
            ("InfluxDB", engine.check_influxdb),
            ("RabbitMQ", engine.check_rabbitmq),
            ("MinIO", engine.check_minio),
            ("Keycloak", engine.check_keycloak),
            ("Nginx", engine.check_nginx),
            ("Telegraf", engine.check_telegraf),
            ("Ansible", engine.check_ansible),
        ]
        for name, fn in checks:
            log_info_inline(f"验证 {name}")
            result = fn()
            if result == 2:
                log_error(" 中间件验证失败")
                sys.exit(1)
            elif result == 0:
                log_ok()
            else:
                log_ok()
                log_info_inline(f" {name} (本地)")
            log_ok()

        # Install phase
        installs = [
            ("MySQL", "CE_EXTERNAL_MYSQL"),
            ("Redis", "CE_EXTERNAL_REDIS"),
            ("InfluxDB", "CE_EXTERNAL_INFLUXDB"),
            ("RabbitMQ", "CE_EXTERNAL_RABBITMQ"),
            ("MinIO", "CE_EXTERNAL_MINIO"),
            ("Keycloak", "CE_EXTERNAL_KEYCLOAK"),
            ("Nginx", "CE_EXTERNAL_NGINX"),
            ("Telegraf", "CE_EXTERNAL_TELEGRAF"),
            ("Ansible", "CE_EXTERNAL_ANSIBLE"),
        ]
        for name, env_key in installs:
            log_info_inline(f"安装 {name}")
            engine.install(name, env_key)
            log_ok()

        # Configure phase
        configs = [
            ("MySQL", "CE_EXTERNAL_MYSQL",
             f"{engine.install_path}/fit2cloud/conf/mysql"),
            ("Redis", "CE_EXTERNAL_REDIS",
             f"{engine.install_path}/fit2cloud/conf/redis"),
            ("InfluxDB", "CE_EXTERNAL_INFLUXDB", ""),
            ("RabbitMQ", "CE_EXTERNAL_RABBITMQ",
             f"{engine.install_path}/fit2cloud/conf/rabbitmq"),
            ("MinIO", "CE_EXTERNAL_MINIO",
             f"{engine.install_path}/fit2cloud/conf/minio/minio.env"),
            ("Keycloak", "CE_EXTERNAL_KEYCLOAK",
             f"{engine.install_path}/fit2cloud/conf/keycloak"),
            ("Nginx", "CE_EXTERNAL_NGINX",
             f"{engine.install_path}/fit2cloud/conf/nginx/conf.d"),
            ("Telegraf", "CE_EXTERNAL_TELEGRAF",
             f"{engine.install_path}/fit2cloud/conf/telegraf"),
            ("Ansible", "CE_EXTERNAL_ANSIBLE", ""),
        ]
        for name, env_key, path in configs:
            log_info_inline(f"配置 {name}")
            engine.configure(name, env_key, path)
            log_ok()
        mark_step_done("middleware")

    # --- Step 8: Service Up ---
    if not run_step("service_up"):
        log_info_inline("启动服务")
        docker.service_up(ENV_FILE, RUNTIME_ENV)
        mark_step_done("service_up")

    # --- Step 9: Wait for Healthy ---
    if not run_step("wait_for_healthy"):
        access_ip = get_env_value("CE_ACCESS_IP", "127.0.0.1", ENV_FILE)
        wait_for_healthy(f"http://{access_ip}:80")
        mark_step_done("wait_for_healthy")

    log_info("\n安装完成！")
    return 0


def check_environment(args) -> bool:
    """Validate system requirements (mirrors bash check_environment)."""
    # OS check
    os_type = docker.get_os()
    log_info(f"操作系统: {os_type}")
    if not os_type:
        log_error("不支持的操作系统")
        return False

    # Arch check
    arch = os.machine()
    log_info(f"架构: {arch}")

    # Memory check
    try:
        mem_total = Path("/proc/meminfo").read_text()
        mem_kb = int(re.search(r"MemTotal:\s+(\d+)", mem_total).group(1))
        mem_gb = mem_kb / 1024 / 1024
        log_info(f"内存: {mem_gb:.1f} GB")
        if mem_gb < 4:
            log_warn("内存小于 4GB，建议 8GB+")
    except Exception:
        pass

    # Disk check
    try:
        stat = os.statvfs("/opt")
        free_gb = stat.f_bavail * stat.f_frsize / (1024**3)
        log_info(f"可用磁盘: {free_gb:.1f} GB")
        if free_gb < 10:
            log_warn("可用磁盘小于 10GB，建议 50GB+")
    except Exception:
        pass

    return True


def ensure_dirs(install_path: str) -> None:
    """Create required directories (mirrors ensure_dir in bash)."""
    dirs = [
        f"{install_path}/fit2cloud",
        f"{install_path}/fit2cloud/conf",
        f"{install_path}/fit2cloud/data",
        f"{install_path}/fit2cloud/bin",
    ]
    for d in dirs:
        Path(d).mkdir(parents=True, exist_ok=True)


def render_config(install_env: str, runtime_env: str) -> None:
    """Render templates from .tpl files (mirrors bash do_render)."""
    # Find render-cfg binary
    binary = None
    candidates = [
        "./ce-render-cfg",
        "/opt/fit2cloud/ce-render-cfg",
        "./render-cfg",
    ]
    for c in candidates:
        if Path(c).exists():
            binary = c
            break

    # Try to find in PATH
    if not binary:
        result = subprocess.run(["which", "ce-render-cfg"],
                                capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            binary = result.stdout.strip()

    if not binary:
        log_warn("ce-render-cfg not found, skipping render")
        return

    # Gather encryption keys
    data = read_env_file(install_env)
    encryption_key = data.get("CE_ENCRYPTION_KEY", "defaultkey")
    encryption_rsa_private_key = data.get("CE_ENCRYPTION_RSA_PRIVATE_KEY", "")

    env_files = [install_env]
    if Path(runtime_env).exists():
        env_files.append(runtime_env)

    # Collect tpl files
    tpl_files = []
    for p in Path(".").rglob("*.tpl"):
        tpl_files.append(str(p))

    if not tpl_files:
        log_info("No template files found")
        return

    # Render each template
    for tpl in tpl_files:
        output = tpl.replace(".tpl", "")
        cmd = [binary]
        cmd.extend(env_files)
        cmd.extend(["-encryption-key", encryption_key])
        if encryption_rsa_private_key:
            cmd.extend(["-encryption-rsa-private-key", encryption_rsa_private_key])
        cmd.extend(["-f", tpl, "-o", output])

        log_info_inline(f"渲染: {tpl} -> {output}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            log_warn(f"渲染失败 {tpl}: {result.stderr[:200]}")
        else:
            log_ok()


if __name__ == "__main__":
    main()
