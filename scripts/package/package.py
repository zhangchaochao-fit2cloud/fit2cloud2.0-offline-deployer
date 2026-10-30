#!/usr/bin/env python3
"""
Fit2Cloud 2.0 打包脚本（Python 版本）

对应 package.sh 的主入口，解析参数后调用 scripts_py/main.py 的 run_pipeline。

用法:
    python3 package.py [-v 2.0.1] [-b 100] [--dry-run] [--clean]
    python3 package.py --env-file packaging.env -v 2.0.1 -b 100
    python3 package.py --with-python
"""

import os
import sys
import argparse
from pathlib import Path

# Ensure parent directory of this file is on sys.path so we can import
# scripts_py.* (prepare, pull_images, export_images, download_tools, main).
_SCRIPTS_PKG_DIR = Path(__file__).resolve().parent / "scripts_py"
sys.path.insert(0, str(_SCRIPTS_PKG_DIR))

# Also add the shared scripts_py for logger/env
_SHARED_SCRIPTS = Path(__file__).resolve().parent.parent.parent / "opt" / "fit2cloud" / "scripts_py"
sys.path.insert(0, str(_SHARED_SCRIPTS))


# ---------------------------------------------------------------------------
# CLI argument parsing (mirrors bash package.sh)
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Fit2Cloud 2.0 打包脚本（Python 版本）",
        add_help=False,
    )
    parser.add_argument("-h", "--help", action="store_true")
    parser.add_argument("-v", "--version", default=None, help="版本号 [默认: 2.0]")
    parser.add_argument("-b", "--build-number", default=None, help="构建号 [默认: 1]")
    parser.add_argument("-V", "--image-version", default=None, help="镜像 tag")
    parser.add_argument("-r", "--registry", default=None, help="镜像仓库地址")
    parser.add_argument("-o", "--output-dir", default=None, help="输出目录")
    parser.add_argument("--platform", default=None, help="目标平台 [默认: amd64]")
    parser.add_argument("--dry-run", action="store_true", help="试运行模式")
    parser.add_argument("--clean", action="store_true", help="清理临时文件")
    parser.add_argument("-p", "--plugin-packages", default=None, help="插件包目录（逗号分隔）")
    parser.add_argument("-d", "--deployment-packages", default=None, help="中间件包 URL（逗号分隔）")
    parser.add_argument("-e", "--extension-packages", default=None, help="扩展包 URL（逗号分隔）")
    parser.add_argument("--env-file", default=None, help="打包环境文件")
    parser.add_argument("--skip-render-cfg", action="store_true", help="跳过 ce-render-cfg 编译")
    parser.add_argument("--with-python", action="store_true", help="包含 Python 版本脚本")
    parser.add_argument("--concurrency", type=int, default=8, help="镜像拉取并发数 [默认: 8]")

    args = parser.parse_args()

    if args.help:
        print(f"""Fit2Cloud 2.0 打包脚本（Python 版本）

用法: python3 package.py [选项]

选项:
    -h, --help              显示此帮助信息
    -v, --version VERSION   版本号 [默认: 2.0]
    -b, --build-number NUM  构建号 [默认: 1]
    -V, --image-version TAG 镜像 tag [默认: <版本号>.<构建号>]
    -r, --registry URL      镜像仓库地址 [默认: registry.fit2cloud.com/north]
    -o, --output-dir DIR    输出目录 [默认: ./dist]
    --platform PLATFORM     目标平台 [默认: amd64]
    --dry-run               试运行模式
    --clean                 清理临时文件
    -p, --plugin-packages   插件包目录（多个用逗号分隔）
    -d, --deployment-packages 中间件包 URL（逗号分隔）
    -e, --extension-packages 扩展包 URL（逗号分隔）
    --env-file FILE         打包环境文件
    --skip-render-cfg       跳过 ce-render-cfg 编译
    --with-python           包含 Python 版本脚本
    --concurrency N         镜像拉取并发数 [默认: 8]

示例:
    python3 package.py -v 2.0.1 -b 100
    python3 package.py -r my-registry.com -v 2.0.1 --platform arm64
    python3 package.py --env-file packaging.env -v 2.0.1 -b 100
    python3 package.py --dry-run -v 2.0.1
""")
        sys.exit(0)

    return args


def load_env_file(env_file, defaults):
    """Load env file and fill in defaults for args not explicitly set via CLI.

    Since argparse doesn't tell us which args were explicit, we use a convention:
    env-file always acts as defaults (never overrides).  The user must not supply
    both --env-file and a conflicting --flag.
    """
    if not env_file or not Path(env_file).exists():
        return

    from env import read_env_file  # noqa: E402
    data = read_env_file(env_file)

    # Export download / image URLs to environment (used by download_tools)
    for key in ("DOCKER_PACKAGE_URL", "DOCKER_PACKAGE_URL_ARM64",
                "DOCKER_PACKAGE_URL_RHEL8", "TELEGRAF_PACKAGE_URL",
                "MINIO_DOCKER_IMAGE", "FROM_DOCKER_LOCAL_DIR"):
        if key in data:
            os.environ[key] = data[key]

    # Fill defaults
    if not defaults.get("version") and data.get("FIT2CLOUD_VERSION"):
        defaults["version"] = data["FIT2CLOUD_VERSION"]
    if not defaults.get("build_number") and data.get("BUILD_NUMBER"):
        defaults["build_number"] = data["BUILD_NUMBER"]
    if not defaults.get("image_version") and data.get("VERSION"):
        defaults["image_version"] = data["VERSION"]
    if not defaults.get("registry") and data.get("REGISTRY_URL"):
        defaults["registry"] = data["REGISTRY_URL"]
    if not defaults.get("platform") and data.get("PLATFORM"):
        defaults["platform"] = data["PLATFORM"]
    if not defaults.get("output_dir") and data.get("OUTPUT_DIR"):
        defaults["output_dir"] = data["OUTPUT_DIR"]
    if not defaults.get("with_python") and data.get("WITH_PYTHON") in ("true", "True", "1"):
        defaults["with_python"] = True
    if not defaults.get("plugin_packages") and data.get("PLUGIN_PACKAGES"):
        defaults["plugin_packages"] = data["PLUGIN_PACKAGES"]
    if not defaults.get("deployment_packages") and data.get("DEPLOYMENT_PACKAGES"):
        defaults["deployment_packages"] = data["DEPLOYMENT_PACKAGES"]
    if not defaults.get("extension_packages") and data.get("EXTENSION_PACKAGES"):
        defaults["extension_packages"] = data["EXTENSION_PACKAGES"]


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    args = parse_args()

    # Collect CLI values as explicit overrides
    defaults = {}
    if args.version is not None:
        defaults["version"] = args.version
    if args.build_number is not None:
        defaults["build_number"] = args.build_number
    if args.image_version is not None:
        defaults["image_version"] = args.image_version
    if args.registry is not None:
        defaults["registry"] = args.registry
    if args.output_dir is not None:
        defaults["output_dir"] = args.output_dir
    if args.platform is not None:
        defaults["platform"] = args.platform
    if args.with_python:
        defaults["with_python"] = True
    if args.plugin_packages is not None:
        defaults["plugin_packages"] = args.plugin_packages
    if args.deployment_packages is not None:
        defaults["deployment_packages"] = args.deployment_packages
    if args.extension_packages is not None:
        defaults["extension_packages"] = args.extension_packages

    # Load env-file defaults
    load_env_file(args.env_file, defaults)

    # Apply resolved defaults to args
    args.version = defaults.get("version", "2.0")
    args.build_number = defaults.get("build_number", "1")
    args.image_version = defaults.get("image_version")
    args.registry = defaults.get("registry", "registry.fit2cloud.com/north")
    args.platform = defaults.get("platform", "amd64")
    args.with_python = defaults.get("with_python", False)
    args.plugin_packages = defaults.get("plugin_packages", "")
    args.deployment_packages = defaults.get("deployment_packages", "")
    args.extension_packages = defaults.get("extension_packages", "")

    # Set IMAGE_VERSION as alias
    if not args.image_version:
        args.image_version = f"{args.version}.{args.build_number}"

    # Import and run the pipeline from main.py
    from main import run_pipeline  # noqa: E402

    result = run_pipeline(args)
    if result:
        sys.exit(0)


if __name__ == "__main__":
    main()
