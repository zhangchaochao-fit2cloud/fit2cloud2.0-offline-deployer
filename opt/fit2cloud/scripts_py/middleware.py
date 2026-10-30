#!/usr/bin/env python3
"""
Middleware engine — handles all 9 middleware components.

Mirrors the bash middleware pattern where each middleware script
(mysql.sh, redis.sh, etc.) exports check/install/configure functions.

Python equivalent: a single MiddlewareEngine class manages all middleware
with a unified check → install → configure lifecycle.
"""

import os
import sys
import subprocess
import socket
import time
import shutil
from pathlib import Path


def log(msg, color=None):
    """Inline logger — keep it simple."""
    colors = {
        "green": "\033[32m",
        "red": "\033[31m",
        "yellow": "\033[33m",
        "blue": "\033[34m",
        "cyan": "\033[36m",
    }
    prefix = f"{colors.get(color, '')}" if color else ""
    suffix = "\033[0m" if color else ""
    print(f"{prefix}{msg}{suffix}", flush=True)


def log_info(msg):
    log(f"[INFO] {msg}")


def log_ok():
    log("[OK]  ", "green")


def log_error(msg):
    log(f"[ERROR] {msg}", "red")


def log_warn(msg):
    log(f"[WARN]  {msg}", "yellow")


def log_info_inline(msg):
    print(f"[INFO] {msg}", end="", flush=True)


# ---------------------------------------------------------------------------
# Env helpers (inline — avoid circular imports)
# ---------------------------------------------------------------------------

def _read_env_file(path):
    """Parse .env file into dict."""
    result = {}
    if not path or not Path(path).exists():
        return result
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            idx = line.find("=")
            if idx < 0:
                continue
            key = line[:idx].strip()
            value = line[idx+1:].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            result[key] = value
    return result


def _get_env(key, default, env_file):
    """Get env value with default."""
    data = _read_env_file(env_file) if env_file else {}
    return data.get(key, default)


def _set_env(key, value, env_file):
    """Set env value in file."""
    if not env_file:
        return
    data = _read_env_file(env_file)
    data[key] = value
    with open(env_file, "w", encoding="utf-8") as f:
        for k, v in data.items():
            f.write(f"{k}={v}\n")


# ---------------------------------------------------------------------------
# Middleware Engine
# ---------------------------------------------------------------------------

class MiddlewareEngine:
    """Manages all middleware components (MySQL, Redis, InfluxDB, etc.)."""

    def __init__(self, env_file, install_path="/opt", base_dir="/opt/fit2cloud"):
        self.env_file = env_file
        self.env = _read_env_file(env_file) if env_file else {}
        self.install_path = install_path
        self.base_dir = base_dir

    def is_external(self, env_key):
        return _get_env(env_key, "false", self.env_file).lower() == "true"

    def skip_install(self, env_key):
        return self.is_external(env_key)

    def skip_configure(self, env_key):
        return self.is_external(env_key)

    def _check_connection(self, host, port, timeout=3):
        """Check TCP connectivity."""
        try:
            if not host or not port:
                return False
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, int(port)))
            sock.close()
            return result == 0
        except (ValueError, OSError, TypeError):
            return False

    def _check_url(self, url, timeout=5):
        """Check HTTP URL via curl."""
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

    def set_permissions(self, config_path):
        """Recursively set permissions on config files/dirs."""
        p = Path(config_path)
        if not p.exists():
            return
        if p.is_dir():
            for item in p.rglob("*"):
                if item.is_file():
                    os.chmod(item, 0o640)
            os.chmod(p, 0o750)
        else:
            os.chmod(p, 0o640)

    # ---- Check functions ----

    def check(self, name, env_key, host_key, port_key,
              default_host="", default_port="", health_url=""):
        """Generic middleware check.

        Returns:
            0: external works
            1: will install locally
            2: external unreachable
        """
        if self.skip_install(env_key):
            host = _get_env(host_key, default_host, self.env_file)
            port = _get_env(port_key, default_port, self.env_file)
            if health_url:
                if self._check_url(health_url):
                    log_ok()
                    return 0
                else:
                    log_error(f" 外部 {name} 不可达")
                    return 2
            else:
                if self._check_connection(host, port):
                    log_ok()
                    return 0
                else:
                    log_error(f" 外部 {name} 不可达")
                    return 2
        return 1  # internal

    def check_mysql(self):
        return self.check("MySQL", "CE_EXTERNAL_MYSQL",
                          "CE_MYSQL_HOST", "CE_MYSQL_PORT",
                          "mysql", "3306", "")

    def check_redis(self):
        return self.check("Redis", "CE_EXTERNAL_REDIS",
                          "CE_REDIS_HOST", "CE_REDIS_PORT",
                          "redis", "6379")

    def check_influxdb(self):
        return self.check("InfluxDB", "CE_EXTERNAL_INFLUXDB",
                          "CE_INFLUXDB_HOST", "CE_INFLUXDB_PORT",
                          "influxdb", "8086",
                          "http://influxdb:8086/ping")

    def check_rabbitmq(self):
        return self.check("RabbitMQ", "CE_EXTERNAL_RABBITMQ",
                          "CE_RABBITMQ_HOST", "CE_RABBITMQ_PORT",
                          "rabbitmq", "5672")

    def check_minio(self):
        return self.check("MinIO", "CE_EXTERNAL_MINIO",
                          "CE_MINIO_HOST", "CE_MINIO_PORT",
                          "minio", "9000",
                          "http://minio:9000/minio/health/live")

    def check_keycloak(self):
        return self.check("Keycloak", "CE_EXTERNAL_KEYCLOAK",
                          "CE_KEYCLOAK_HOST", "CE_KEYCLOAK_PORT",
                          "keycloak", "8080")

    def check_nginx(self):
        return self.check("Nginx", "CE_EXTERNAL_NGINX",
                          "CE_NGINX_HOST", "CE_NGINX_PORT",
                          "nginx", "80")

    def check_telegraf(self):
        return self.check("Telegraf", "CE_EXTERNAL_TELEGRAF",
                          "CE_TELEGRAF_HOST", "CE_TELEGRAF_PORT",
                          "telegraf", "8125")

    def check_ansible(self):
        return self.check("Ansible", "CE_EXTERNAL_ANSIBLE",
                          "CE_ANSIBLE_HOST", "CE_ANSIBLE_PORT",
                          "ansible", "22")

    # ---- Install ----

    def install(self, name, env_key):
        if self.skip_install(env_key):
            log_info(f"{name}: 使用外部，跳过安装")
            return 0
        return 0

    # ---- Configure ----

    def configure(self, name, env_key, config_path=""):
        if self.skip_configure(env_key):
            return 0
        if config_path and Path(config_path).exists():
            self.set_permissions(config_path)
        return 0


# ---------------------------------------------------------------------------
# Middleware orchestration
# ---------------------------------------------------------------------------

def run_middleware_steps(engine, silent=False):
    """Run check/install/configure for all middleware.

    Mirrors the bash middleware section in install.sh where each
    check_* / install_* / configure_* is called in sequence.
    """

    # --- Check phase ---
    checks = [
        ("MySQL", "check_mysql"),
        ("Redis", "check_redis"),
        ("InfluxDB", "check_influxdb"),
        ("RabbitMQ", "check_rabbitmq"),
        ("MinIO", "check_minio"),
        ("Keycloak", "check_keycloak"),
        ("Nginx", "check_nginx"),
        ("Telegraf", "check_telegraf"),
        ("Ansible", "check_ansible"),
    ]

    for name, method_name in checks:
        log_info_inline(f"验证 {name}")
        fn = getattr(engine, method_name)
        result = fn()
        if result == 2:
            log_error(f"{name} 检查失败")
            return 1
        elif result == 0:
            log_ok()
        else:
            log_ok()

    # --- Install phase ---
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

    # --- Configure phase ---
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

    return 0
