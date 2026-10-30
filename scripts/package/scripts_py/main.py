#!/usr/bin/env python3
"""
打包主入口 — 对应 package.sh + create-package.sh。

整合所有打包阶段，生成最终的 tar.gz 安装包。
"""

import os
import sys
import json
import subprocess
import shutil
import tarfile
import hashlib
from pathlib import Path
from datetime import datetime

# Parent: scripts/package/scripts_py → opt/fit2cloud/scripts_py
_SCRIPTS_PY = Path(__file__).resolve().parent.parent.parent / "opt" / "fit2cloud" / "scripts_py"
sys.path.insert(0, str(_SCRIPTS_PY))

from logger import (
    log_info, log_warn, log_error, log_ok, log_success,
    log_info_inline, log_step_success, log_step_error,
    print_title, print_subtitle,
)

# Import sub-stages (same directory, no package prefix)
from prepare import prepare as prepare_step
from pull_images import pull_images as pull_images_step
from export_images import export_images as export_images_step
from download_tools import download_tools as download_tools_step


def ensure_dir(path):
    """确保目录存在。"""
    Path(path).mkdir(parents=True, exist_ok=True)


def get_env_value(env_file, key, default=""):
    """从 env 文件读取值。"""
    from env import read_env_file
    data = read_env_file(env_file)
    return data.get(key, default)


def set_env_value(env_file, key, value):
    """设置 env 文件中的值。"""
    from env import set_env_value as _set
    _set(key, value, env_file)


def copy_file_sha256(src, dst):
    """复制文件并计算 SHA256。"""
    shutil.copy2(str(src), str(dst))
    return _sha256_file(dst)


def _sha256_file(path):
    """计算文件的 SHA256。"""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _get_all_files(directory):
    """递归获取所有文件路径。"""
    result = []
    d = Path(directory)
    if not d.exists():
        return result
    for p in sorted(d.rglob("*")):
        if p.is_file():
            result.append(str(p.relative_to(d)))
    return result


def create_package(output_dir, installer_dir, build_id, platform, report_file):
    """创建最终 tar.gz 包。

    对应 bash create-package.sh。
    """
    print_title("步骤 5/5: 创建安装包")

    output = Path(output_dir)
    installer = Path(installer_dir)
    now = datetime.now()

    # 生成包名
    version = get_env_value(str(installer / "fit2cloud" / ".env"), "VERSION", "dev-preview")
    package_filename = f"cloudexplorer-{version}.tar.gz"
    package_path = output / package_filename

    log_info(f"创建安装包: {package_filename}")
    log_info(f"构建标识: {build_id}")
    log_info(f"平台: {platform}")

    if report_file:
        report_dir = os.path.dirname(os.path.abspath(report_file))
        os.makedirs(report_dir, exist_ok=True)

    # 生成 manifest.txt
    manifest_lines = [
        f"build_id={build_id}",
        f"build_time={now.strftime('%Y-%m-%d %H:%M:%S')}",
        f"platform={platform}",
        "",
        "# SHA256 checksums",
    ]

    # 遍历安装包内容，计算 checksums
    files = _get_all_files(str(installer))
    for rel_path in files:
        full_path = installer / rel_path
        checksum = _sha256_file(str(full_path))
        manifest_lines.append(f"{checksum}  {rel_path}")

    manifest_path = installer / "manifest.txt"
    with open(manifest_path, "w") as f:
        f.write("\n".join(manifest_lines) + "\n")
    log_info("manifest.txt 已生成")

    # 记录 Python 版本信息
    if (installer / "fit2cloud" / "scripts_py" / ".version").exists():
        with open(installer / "fit2cloud" / "scripts_py" / ".version") as f:
            version_info = f.read()
        manifest_lines = [
            f"build_id={build_id}",
            f"build_time={now.strftime('%Y-%m-%d %H:%M:%S')}",
            f"platform={platform}",
            "python_version=experimental",
        ]
        for line in version_info.splitlines():
            if line.startswith("build_version="):
                manifest_lines.append(f"python_build={line.split('=', 1)[1]}")
            if line.startswith("build_time="):
                manifest_lines.append(f"python_build_time={line.split('=', 1)[1]}")
        manifest_lines.append("")
        manifest_lines.append("# SHA256 checksums")

        # 重新计算 checksums
        files = _get_all_files(str(installer))
        for rel_path in files:
            full_path = installer / rel_path
            checksum = _sha256_file(str(full_path))
            manifest_lines.append(f"{checksum}  {rel_path}")

        with open(manifest_path, "w") as f:
            f.write("\n".join(manifest_lines) + "\n")

    # 创建 tar.gz（排除 manifest.txt 本身）
    log_info(f"打包 {len(files)} 个文件...")
    with tarfile.open(str(package_path), "w:gz", compresslevel=9) as tar:
        for rel_path in files:
            if rel_path == "manifest.txt":
                continue
            full_path = installer / rel_path
            tar.add(str(full_path), arcname=rel_path)

    # 再把 manifest.txt 加进去（放在最后）
    with tarfile.open(str(package_path), "a:gz") as tar:
        tar.add(str(manifest_path), arcname="manifest.txt")

    # 文件大小
    file_size = os.path.getsize(str(package_path))
    size_mb = file_size / (1024 * 1024)

    # 写报告
    if report_file:
        with open(report_file, "w") as f:
            json.dump({
                "package": package_filename,
                "path": str(package_path),
                "size_mb": round(size_mb, 2),
                "files": len(files),
                "build_id": build_id,
                "platform": platform,
                "build_time": now.strftime("%Y-%m-%d %H:%M:%S"),
            }, f, indent=2)

    log_success(f"安装包已创建: {package_filename} ({size_mb:.1f} MB, {len(files)} 个文件)")
    return str(package_path)


def show_package_info(version, build_number, platform, registry_url, output_dir, package_file):
    """显示打包结果信息。"""
    print_title(f"Fit2Cloud {version} 打包完成！")
    print()
    print("=" * 70)
    print("打包信息")
    print("=" * 70)
    print(f"版本:      {version}")
    print(f"构建号:    {build_number}")
    print(f"平台:      {platform}")
    print(f"镜像仓库:  {registry_url}")
    print(f"输出目录:  {output_dir}")
    print(f"安装包:    {package_file}")
    print("=" * 70)
    print()


def run_pipeline(args):
    """主打包流水线。

    Args:
        args: argparse.Namespace 包含所有参数
    """
    # 解析参数
    base_dir = Path(args.base_dir) if args.base_dir else Path.cwd()
    output_dir = str(base_dir / "dist")
    if args.output_dir:
        output_dir = args.output_dir

    installer_dir = os.path.join(output_dir, "installer")
    docker_images_dir = os.path.join(installer_dir, "docker-images")
    tools_dir = os.path.join(installer_dir, "fit2cloud", "tools")
    installer_env = os.path.join(installer_dir, "fit2cloud", ".env")

    # 每次构建清理
    os.makedirs(output_dir, exist_ok=True)

    # 设置环境变量
    env_vars = {
        "REGISTRY_URL": args.registry or "registry.fit2cloud.com/north",
        "FIT2CLOUD_VERSION": args.version or "2.0",
        "BUILD_NUMBER": args.build_number or "1",
        "PLATFORM": args.platform or "amd64",
        "DRY_RUN": str(args.dry_run).lower(),
        "WITH_PYTHON": str(args.with_python).lower(),
    }
    version = f"{env_vars['FIT2CLOUD_VERSION']}.{env_vars['BUILD_NUMBER']}"
    if args.image_version:
        version = args.image_version

    for k, v in env_vars.items():
        os.environ[k] = v

    # Stage 1: Prepare
    prepare_step(
        output_dir=output_dir,
        installer_dir=installer_dir,
        base_dir=str(base_dir),
        version=env_vars["FIT2CLOUD_VERSION"],
        build_number=env_vars["BUILD_NUMBER"],
        registry_url=env_vars["REGISTRY_URL"],
        platform=env_vars["PLATFORM"],
        with_python=(env_vars["WITH_PYTHON"] == "true"),
    )

    # Set env values
    set_env_value(installer_env, "IMAGE_ADDRESS", env_vars["REGISTRY_URL"])
    set_env_value(installer_env, "PLATFORM", env_vars["PLATFORM"])

    # Stage 2: Pull images
    pull_report = os.path.join(output_dir, "pull-report.json")
    ret = pull_images_step(
        env_file=installer_env,
        report_file=pull_report,
        concurrency=args.concurrency or 8,
        dry_run=(env_vars["DRY_RUN"] == "true"),
    )
    if ret != 0:
        log_error("镜像拉取阶段失败，中止打包")
        sys.exit(1)

    # Stage 3: Export images
    export_report = os.path.join(output_dir, "export-report.json")
    export_images_step(
        images_dir=docker_images_dir,
        env_file=installer_env,
        report_file=export_report,
        dry_run=(env_vars["DRY_RUN"] == "true"),
    )

    # Stage 4: Download tools
    download_tools_step(tools_dir)

    # Stage 5: Create package
    build_id = f"{env_vars['FIT2CLOUD_VERSION']}.{env_vars['BUILD_NUMBER']} Build {datetime.now().strftime('%Y%m%d%H%M')}"
    package_path = create_package(
        output_dir=output_dir,
        installer_dir=installer_dir,
        build_id=build_id,
        platform=env_vars["PLATFORM"],
        report_file=os.path.join(output_dir, "package-report.json"),
    )

    # Clean temp if requested
    if args.clean:
        shutil.rmtree(installer_dir, ignore_errors=True)
        log_info("临时文件已清理")

    # Show result
    show_package_info(
        version=env_vars["FIT2CLOUD_VERSION"],
        build_number=env_vars["BUILD_NUMBER"],
        platform=env_vars["PLATFORM"],
        registry_url=env_vars["REGISTRY_URL"],
        output_dir=output_dir,
        package_file=package_path,
    )

    return package_path
