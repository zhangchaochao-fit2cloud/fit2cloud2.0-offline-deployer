#!/usr/bin/env python3
"""
并行拉取 Docker 镜像 — 替代 bash pull-images.sh。

性能优化：
- ThreadPoolExecutor 替代 bash 后台进程（避免每个 pull 子进程的 fork 开销）
- 并发度可调（默认 8）
- 3 次重试机制
- 架构验证
"""

import os
import sys
import json
import subprocess
import shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

# Parent: scripts/package/scripts_py → scripts/package/scripts_py → opt/fit2cloud
_SCRIPTS_PY = Path(__file__).resolve().parent.parent.parent / "opt" / "fit2cloud" / "scripts_py"
sys.path.insert(0, str(_SCRIPTS_PY))

from logger import (
    log_info, log_warn, log_error, log_ok, log_step_success,
    log_info_inline, log_step_error, log_success,
    print_title,
)


def cmd_exists(cmd):
    return subprocess.run(["which", cmd], capture_output=True, timeout=2).returncode == 0


def detect_compose_cmd():
    result = subprocess.run(
        ["docker", "compose", "version"],
        capture_output=True, timeout=5,
    )
    if result.returncode == 0:
        return "docker compose"
    if cmd_exists("docker-compose"):
        return "docker-compose"
    return None


def get_all_images(env_file):
    """解析 docker compose config 中的所有镜像名。"""
    compose_cmd = detect_compose_cmd()
    if not compose_cmd:
        return []
    result = subprocess.run(
        compose_cmd.split() + ["config"],
        capture_output=True, text=True, timeout=30,
        cwd=str(Path(env_file).parent),
    )
    if result.returncode != 0:
        return []
    images = []
    for line in result.stdout.splitlines():
        if "image:" in line:
            parts = line.split()
            if len(parts) >= 2:
                img = parts[1].strip('"')
                if img:
                    images.append(img)
    return images


def read_env_value(env_file, key, default=""):
    """从 .env 文件读取单个值。"""
    p = Path(env_file)
    if not p.exists():
        return default
    with open(p, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or not line or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == key:
                return v.strip()
    return default


def verify_image_arch(image_name, expected_platform):
    """验证镜像架构，不匹配则警告。"""
    result = subprocess.run(
        ["docker", "inspect", "--format={{.Architecture}}", image_name],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        return
    arch = result.stdout.strip()
    if arch and arch != expected_platform:
        log_warn(f"镜像 {image_name} 架构为 {arch}, 期望 {expected_platform}")


def _pull_one(image_name, platform, tmpdir, idx):
    """拉取单个镜像，最多重试 3 次。

    使用 Popen + wait 避免 subprocess.run 的额外开销。
    结果写入 tmpdir/result_$idx。
    """
    attempt = 1
    while attempt <= 3:
        proc = subprocess.Popen(
            ["docker", "pull", f"--platform=linux/{platform}", image_name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        retcode = proc.wait()
        if retcode == 0:
            with open(os.path.join(tmpdir, f"result_{idx}"), "w") as f:
                f.write("ok")
            return "ok"
        if attempt < 3:
            log_info(f"拉取失败，重试 ({attempt}/3): {image_name.split('/')[-1]}")
        attempt += 1

    with open(os.path.join(tmpdir, f"result_{idx}"), "w") as f:
        f.write("fail")
    return "fail"


def pull_images(env_file, report_file, concurrency=8, dry_run=False):
    """并行拉取所有 Docker 镜像。

    Args:
        env_file: .env 文件路径
        report_file: JSON 报告输出路径
        concurrency: 并发数（默认 8）
        dry_run: 是否跳过实际拉取
    Returns:
        0=成功, 1=有失败
    """
    print_title("步骤 2/5: 拉取 Docker 镜像")

    image_list = get_all_images(env_file)
    platform = read_env_value(env_file, "PLATFORM", "amd64")

    if not image_list:
        log_error(f"未从 docker compose 配置中解析到任何镜像，请检查 {env_file}")
        return 1

    total = len(image_list)
    pulled = 0
    failed = 0

    if dry_run:
        for image_name in image_list:
            tag_name = image_name.split("/")[-1].split(":")[0]
            log_info_inline(tag_name)
            log_step_success("跳过")
            pulled += 1
    else:
        tmpdir = f"/tmp/f2c_pull_{os.getpid()}"
        os.makedirs(tmpdir, exist_ok=True)

        try:
            with ThreadPoolExecutor(max_workers=concurrency) as executor:
                futures = {}
                for idx, image_name in enumerate(image_list):
                    tag_name = image_name.split("/")[-1].split(":")[0]
                    log_info_inline(tag_name)
                    future = executor.submit(_pull_one, image_name, platform, tmpdir, idx)
                    futures[future] = idx

                for future in as_completed(futures):
                    result = future.result()
                    if result == "ok":
                        pulled += 1
                    else:
                        failed += 1

            # 验证架构
            for idx in range(total):
                result_path = os.path.join(tmpdir, f"result_{idx}")
                if os.path.exists(result_path):
                    with open(result_path) as f:
                        if f.read().strip() == "ok":
                            verify_image_arch(image_list[idx], platform)

        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    # 写报告
    if report_file:
        os.makedirs(os.path.dirname(os.path.abspath(report_file)), exist_ok=True)
        with open(report_file, "w") as f:
            json.dump({
                "total": total,
                "pulled": pulled,
                "failed": failed,
                "platform": platform,
            }, f, indent=2)

    log_info(f"镜像拉取完成: 成功 {pulled}/{total}, 失败 {failed}")
    if failed > 0:
        log_error(f"有 {failed} 个镜像拉取失败")
        return 1
    return 0
