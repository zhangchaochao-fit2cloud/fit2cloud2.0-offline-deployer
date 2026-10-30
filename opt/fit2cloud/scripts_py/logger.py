#!/usr/bin/env python3
"""
日志模块 — 对齐 bash common.sh 的颜色输出函数。
不引入外部依赖，仅用 ANSI 转义。
"""

import sys

# ANSI 颜色
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"
NC = "\033[0m"


def _padding(msg: str, total: int = 70) -> str:
    """计算等宽填充空格，处理中文字符（占 2 列）"""
    c1 = sum(1 for c in msg if not ("\u4e00" <= c <= "\u9fff"))
    c2 = sum(1 for c in msg if "\u4e00" <= c <= "\u9fff")
    return " " * (total - c1 - c2 * 2)


def log_info_inline(msg: str) -> None:
    pad = _padding(msg)
    sys.stdout.write(f"{GREEN}[INFO] {NC} {msg} {pad}")
    sys.stdout.flush()


def log_info(msg: str) -> None:
    print(f"{GREEN}[INFO] {NC}{msg}")


def log_warn(msg: str) -> None:
    print(f"{YELLOW}[WARN] {NC} {msg}")


def log_step_warn(msg: str) -> None:
    print(f"{YELLOW}{msg}{NC}")


def log_error(msg: str) -> None:
    print(f"{RED}[ERROR] {NC} {msg}", file=sys.stderr)


def log_step_error(msg: str) -> None:
    print(f"{RED}{msg}{NC}")


def log_ok(detail: str = "") -> None:
    print(f"{CYAN}OK{NC} {detail}".strip())


def log_step_success(msg: str) -> None:
    print(f"{CYAN}{msg}{NC} ")


def log_success(msg: str) -> None:
    print(f"{CYAN}[SUCCESS]{NC} {msg}")


def print_title(msg: str) -> None:
    print(f"\n\n{CYAN}******************************\t {msg} \t******************************{NC}\n")


def print_subtitle(msg: str) -> None:
    print(f"\n{BLUE}------------------\t {msg} \t------------------{NC}\n")
