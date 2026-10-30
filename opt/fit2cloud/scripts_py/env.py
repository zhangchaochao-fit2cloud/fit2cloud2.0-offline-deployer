#!/usr/bin/env python3
"""
Environment file operations — mirrors common.sh env functions.

Mirrors:
  get_env_value(key, default, path)
  set_env_value(key, value, path)
  merge_env_files(output, *inputs)
  load_env(path)
"""

import re
import os
from pathlib import Path


def read_env_file(path: str) -> dict:
    """Parse a .env file into a dict, preserving insertion order.

    Ignores blank lines and comments (lines starting with #).
    Handles simple KEY=VALUE and KEY='VALUE' / KEY="VALUE" forms.
    """
    result = {}
    p = Path(path)
    if not p.exists():
        return result

    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # Split on first '=' only
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", line)
            if not m:
                continue
            key = m.group(1)
            value = m.group(2).strip()
            # Strip surrounding quotes
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            result[key] = value
    return result


def get_env_value(key: str, default: str, env_file: str) -> str:
    """Get a value from env_file, falling back to default if missing."""
    data = read_env_file(env_file)
    return data.get(key, default)


def set_env_value(key: str, value: str, env_file: str) -> None:
    """Insert or update a KEY=VALUE line in the env file.

    If key exists, replace the line in-place. Otherwise append.
    Uses a temp file + atomic rename to avoid corruption.
    """
    p = Path(env_file)
    if not p.exists():
        # File doesn't exist yet — create parent dirs, write single line
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(env_file, "w", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")
        return

    data = read_env_file(env_file)
    data[key] = value

    # Write back with same format: comments preserved, keys in order
    _write_env_file(env_file, data, key)


def _write_env_file(path: str, data: dict, updated_key: str) -> None:
    """Rewrite env file preserving comment structure, updating only updated_key."""
    p = Path(path)
    tmp_path = str(p) + ".tmp"
    with open(p, "r", encoding="utf-8") as f:
        original_lines = f.readlines()

    with open(tmp_path, "w", encoding="utf-8") as f:
        # Track if we've already replaced this key
        replaced = False
        for line in original_lines:
            stripped = line.strip()
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", stripped)
            if m and m.group(1) == updated_key and not replaced:
                replaced = True
                f.write(f"{updated_key}={data[updated_key]}\n")
            elif stripped == "" or stripped.startswith("#"):
                f.write(line)
            else:
                # Non-comment, non-matching key line — keep original
                f.write(line)

        if not replaced:
            f.write(f"{updated_key}={data[updated_key]}\n")

    # Atomic-ish replace
    os.replace(tmp_path, str(p))


def merge_env_files(output: str, *inputs: str) -> None:
    """Merge multiple env files into one. Last file wins for duplicate keys.

    Preserves comments from the first occurrence of each key.
    Equivalent to the awk-based merge_env_files() in bash.
    """
    merged = {}
    comment_map = {}  # key -> first comment seen

    for inp in inputs:
        p = Path(inp)
        if not p.exists():
            continue

        with open(p, "r", encoding="utf-8") as f:
            current_comment = None
            for line in f:
                stripped = line.strip()
                # Track top-level comments
                if stripped.startswith("#"):
                    current_comment = stripped
                    continue
                if not stripped:
                    current_comment = None
                    continue

                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", stripped)
                if not m:
                    continue

                key = m.group(1)
                if key not in comment_map and current_comment:
                    comment_map[key] = current_comment
                    current_comment = None

                value = m.group(2).strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                merged[key] = value

    # Write merged output with comments
    with open(output, "w", encoding="utf-8") as f:
        for key, value in merged.items():
            if key in comment_map:
                f.write(f"{comment_map[key]}\n")
            f.write(f"{key}={value}\n")


def load_env(env_file: str) -> dict:
    """Convenience alias for read_env_file."""
    return read_env_file(env_file)
