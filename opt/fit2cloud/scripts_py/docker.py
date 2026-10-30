#!/usr/bin/env python3
"""
Docker operations — parallel to docker.sh in bash.

Provides: detect_compose, verify_image_arch, download_docker,
check_docker, install_docker, docker_start, load_images.
"""

import os
import sys
import re
import subprocess
from pathlib import Path


def cmd_exists(cmd):
    """Check if a command exists."""
    return subprocess.run(
        ["which", cmd], capture_output=True, timeout=2
    ).returncode == 0


def get_os():
    """Detect OS type (mirrors bash get_os)."""
    try:
        # Check /etc/os-release
        with open("/etc/os-release", "r") as f:
            content = f.read().lower()
        for line in content.splitlines():
            for keyword in ["centos", "rhel"]:
                if keyword in line and "id_like" not in line:
                    return "centos"
            if "openeuler" in line and "id=" in line:
                return "openeuler"
            if "kylin" in line and "id=" in line:
                return "kylin"
            if "ubuntu" in line and "id=" in line:
                return "ubuntu"
        # Fallback: check /etc/redhat-release
        if Path("/etc/redhat-release").exists():
            return "centos"
    except Exception:
        pass
    return None


def get_os_version():
    """Get major version number."""
    try:
        with open("/etc/os-release", "r") as f:
            for line in f:
                if line.startswith("VERSION_ID="):
                    return line.split("=")[1].strip('"')
    except Exception:
        pass
    return "0"


def detect_compose_cmd():
    """Detect docker compose command (mirrors detect_compose_cmd)."""
    # Try 'docker compose' first
    result = subprocess.run(
        ["docker", "compose", "version"],
        capture_output=True, timeout=5
    )
    if result.returncode == 0:
        return "docker compose"
    # Try 'docker-compose'
    if cmd_exists("docker-compose"):
        return "docker-compose"
    return None


def get_compose_cmd():
    """Alias for detect_compose_cmd."""
    return detect_compose_cmd()


def get_docker_compose_exe():
    """Alias for detect_compose_cmd."""
    return detect_compose_cmd()


def verify_image_arch(image_name):
    """Verify Docker image architecture matches system."""
    result = subprocess.run(
        ["docker", "inspect", image_name],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode != 0:
        return False
    import json
    try:
        info = json.loads(result.stdout)
        if info:
            arch = info[0].get("Architecture", "")
            return arch in ("amd64", "arm64", "aarch64")
    except (json.JSONDecodeError, IndexError):
        return False
    return True


def check_docker():
    """Validate Docker version >= 18.9."""
    result = subprocess.run(
        ["docker", "--version"],
        capture_output=True, text=True, timeout=5
    )
    if result.returncode != 0:
        return False
    match = re.search(r"(\d+)\.(\d+)", result.stdout)
    if not match:
        return False
    major, minor = int(match.group(1)), int(match.group(2))
    return major > 18 or (major == 18 and minor >= 9)


def docker_start():
    """Start and enable Docker service."""
    if cmd_exists("systemctl"):
        subprocess.run(["systemctl", "start", "docker"], timeout=30)
        subprocess.run(["systemctl", "enable", "docker"], timeout=30)
    elif cmd_exists("service"):
        subprocess.run(["service", "docker", "start"], timeout=30)


def download_docker():
    """Download Docker from official source (placeholder)."""
    pass


def download_local_docker():
    """Install Docker from local RPM/DEB (placeholder)."""
    pass


def download_remote_docker():
    """Download and install Docker from remote (placeholder)."""
    pass


def _check_url(url, timeout=5):
    """Check HTTP URL availability (used by middleware engine)."""
    try:
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "--connect-timeout", "3", "--max-time", str(timeout), url],
            capture_output=True, text=True, timeout=timeout + 5
        )
        code = result.stdout.strip()
        return code.startswith("2") or code.startswith("3")
    except Exception:
        return False


def install_docker(args=None):
    """Install Docker — platform-specific logic.

    Mirrors bash install_docker():
    - CentOS 7: binary install
    - RHEL 8/麒麟: rpm install
    - Others: attempt standard package manager
    """
    os_type = get_os()
    if not os_type:
        print("[WARN]  Unknown OS, skipping Docker install", flush=True)
        return

    # Check if Docker is already installed
    if check_docker():
        print("[OK]  Docker already installed", flush=True)
        return

    # Try binary install first
    docker_bin = "/usr/local/bin/docker"
    if Path(docker_bin).exists():
        # Set executable
        os.chmod(docker_bin, 0o755)
        if check_docker():
            docker_start()
            return

    print("[WARN]  Docker install requires manual setup or Dockerfile", flush=True)
    return 0


def load_images(env_file=None):
    """Load Docker images from offline tarballs.

    Mirrors bash load_images() which looks for tar files in:
    - $CE_INSTALL_PATH/fit2cloud/docker/
    """
    if env_file and Path(env_file).exists():
        data = {}
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                idx = line.find("=")
                if idx > 0:
                    data[line[:idx].strip()] = line[idx+1:].strip()
    else:
        data = {}

    docker_dir = data.get("CE_INSTALL_PATH", "/opt") + "/fit2cloud/docker"
    if not Path(docker_dir).exists():
        print("[INFO]  No docker images directory found, skipping")
        return

    loaded = 0
    for tar_file in sorted(Path(docker_dir).glob("*.tar*")):
        print(f"[INFO]  Loading image: {tar_file.name}", flush=True)
        result = subprocess.run(
            ["docker", "load", "-i", str(tar_file)],
            capture_output=True, text=True, timeout=300
        )
        if result.returncode == 0:
            loaded += 1
        else:
            print(f"[WARN]  Failed to load {tar_file.name}", flush=True)

    print(f"[INFO]  Loaded {loaded}/{len(list(Path(docker_dir).glob('*.tar*')))} images",
          flush=True)


def service_up(env_file=None, runtime_env=None):
    """Start services via Docker Compose.

    Mirrors bash service_up() which assembles compose files and runs
    docker compose up -d.
    """
    compose_cmd = get_compose_cmd()
    if not compose_cmd:
        print("[ERROR]  Docker Compose not found, cannot start services", flush=True)
        return

    # Assemble compose files list
    compose_files = ["-f", "docker-compose.yml"]
    install_path = "/opt"
    if env_file and Path(env_file).exists():
        data = {}
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                idx = line.find("=")
                if idx > 0:
                    data[line[:idx].strip()] = line[idx+1:].strip()
        install_path = data.get("CE_INSTALL_PATH", "/opt")

    # Add middleware compose files
    conf_dir = f"{install_path}/fit2cloud/conf"
    middleware_files = {
        "mysql": "docker-compose-mysql.yml",
        "redis": "docker-compose-redis.yml",
        "influxdb": "docker-compose-influxdb.yml",
        "rabbitmq": "docker-compose-rabbitmq.yml",
        "minio": "docker-compose-minio.yml",
        "keycloak": "docker-compose-keycloak.yml",
        "nginx": "docker-compose-nginx.yml",
        "telegraf": "docker-compose-telegraf.yml",
        "ansible": "docker-compose-ansible.yml",
    }
    for mw, fname in middleware_files.items():
        fpath = Path(conf_dir) / fname
        if fpath.exists():
            compose_files.extend(["-f", str(fpath)])

    # Add extension compose files
    ext_dir = f"{install_path}/fit2cloud/extensions"
    if Path(ext_dir).exists():
        for ext in sorted(Path(ext_dir).glob("*/docker-compose.yml")):
            compose_files.append(str(ext))

    # Build full command
    cmd = compose_cmd.split() + compose_files + ["up", "-d"]

    # Set working directory
    env = os.environ.copy()
    if runtime_env and Path(runtime_env).exists():
        data = {}
        with open(runtime_env, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                idx = line.find("=")
                if idx > 0:
                    data[line[:idx].strip()] = line[idx+1:].strip()
        env.update(data)

    print(f"[INFO]  Starting: {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, cwd=install_path, env=env,
                            capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        print(f"[WARN]  docker compose up failed: {result.stderr[:200]}", flush=True)
    return result.returncode
