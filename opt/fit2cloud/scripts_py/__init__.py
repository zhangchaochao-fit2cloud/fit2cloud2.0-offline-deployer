# scripts_py — Parallel Python version of the bash installer scripts
#
# This is an EXPERIMENTAL parallel implementation of the bash-based
# offline-deployer. It does NOT replace the bash version.
#
# Modules:
#   logger.py   — Logging functions (mirrors common.sh log_* functions)
#   env.py      — .env file read/write/merge (mirrors get/set_env_value)
#   middleware.py — Middleware engine (Mirrors all 9 middleware scripts)
#   docker.py   — Docker operations (mirrors docker.sh)
#
# Entry point: opt/fit2cloud/install.py
