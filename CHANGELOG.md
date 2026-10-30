# Changelog

All notable changes to the Fit2Cloud 2.0 Offline Deployer will be documented in this file.

## [2.0.0] - 2026-10-27

### Added
- Unified installer from four separate projects into single `fit2cloud2.0-offline-deployer`
- `ce-render-cfg` Go template engine replacing `envsubst`/`gojinja2`
- CLI flags for `install.sh` (`-d/--dir`, `-s/--silent`, `-e/--env`, `-r/--runtime-env`, `--with-nginx`, `--force-reinstall`)
- `install.env.example` with full documentation for all CE_ variables
- `packaging.env.example` separating packaging-time from install-time variables
- Config layering: `install.env.example` (install-time variables: mode/path/access/cluster/component switches) and `runtime.env.example` (runtime variables: middleware/passwords/Nginx/perf/logs/backup) are separate files; install.sh merges them with the packaging `.env` into `<install-dir>/fit2cloud/.env` — the single runtime contract read by f2cctl/compose/re-render
- `-r, --runtime-env` install option; `do_render` accepts comma-separated multiple env files
- `merge_env_files()` in common.sh (last file wins per key)
- Packaging pipeline (`scripts/package/`) with 5 step scripts and JSON reporting
- Middleware scripts restructured to `scripts/middleware/` (one per service)
- Docker Compose V1/V2 auto-detection via `get_docker_compose_exe()`
- Dynamic compose assembly via `service.sh:get_compose_files()` with HA + extension support
- Keycloak healthcheck in base compose
- `--skip-render-cfg` option in `package.sh`
- `ensure_docker_network()` pre-creates `cmp-network` before service start
- `trap rollback ERR` in install.sh for automatic rollback on failure
- `set_env_value()` sed injection protection (escapes `&`/`/`/`\`)
- Password masking in `show_completion_info()`
- `.gitignore` excludes all sensitive conf files (`.env`, `mysql.env`, `minio.env`, `redis.env`, `redis.conf`, `telegraf.conf`, `kapacitor.conf`, `keycloak.properties`)
- All password files converted to `.tpl` templates rendered by `ce-render-cfg`
- `cmp-network` declared as `external: true` in all compose files
- `scripts/verify.sh`: one-shot verification (bash -n all scripts, shellcheck, go vet/build, config render smoke test)
- `f2cctl help` subcommand

### Hardened (script standards audit)
- `tools/minio/minio-install.sh` / `tools/telegraf/telegraf-install.sh` entry scripts now `set -euo pipefail`; sourced library files carry a header note that error handling belongs to the entry script
- Removed error-suppressing `|| true` from 9 real-failure paths (installer file copy, Docker package unzip/rpm install, upgrade backup/compose/f2cctl update, MinIO data copy, Telegraf config copy); kept only idempotent/cleanup/rollback tolerances
- `safe_execute` no longer uses `eval` (signature: `safe_execute "msg" cmd args...`)
- `docker.sh`: Docker download URLs no longer resolved as globals at source time — passed explicitly by `download-tools.sh` (packaging.env overrides honored), falls back to env file then built-in defaults
- `log_ok` no longer references unset `$1` under `set -u`
- shellcheck fixes: `read -r`, quoted command substitutions, `grep -c` instead of `grep|wc -l`, unused `minio_folder` parameter removed, intentional word-splits annotated with disable comments
- Exemptions with documented rationale centralized in `scripts/verify.sh`
- Systemd unit file (`fit2cloud.service`) with `get_docker_compose_exe()`

### Changed
- `common.sh` fully rewritten — unified naming, `function` → `name()`, removed dead functions
- `docker.sh` fully rewritten — removed 360-line duplicate of common.sh, added `verify_image_arch()`
- `os.sh` rewritten with `check_os/arch/cpu/memory/disk` and `check_system_all`
- `install.sh` rewritten with CLI flags, middleware dispatch, correct execution order
- `upgrade.sh` now re-renders config via `do_render()` on upgrade
- All compose files follow `*-docker-compose.yml` naming pattern
- MinIO compose uses `${CE_MINIO_INSTALL_PATH}` volume path
- RabbitMQ compose uses env vars for passwords instead of hardcoded values
- Redis/InfluxDB compose paths fixed to `conf/<name>/<name>.conf`
- `fit2cloud.service` uses `down -t 120` instead of `down -v` (prevents data loss)
- Image tags pinned: minio `RELEASE.2024-01-31T20-20-36Z`, influxdb `1.8.0`, websockify `1.0.0`
- `required` template function fixed to Go syntax `required "msg" .VAR`
- `install.env.example`: `EUREKA_SERVERS`/`MANAGEMENT_PORT` now active fields

### Improved (end-to-end logic)
- Install/upgrade env merge now falls back to `install.env.example`/`runtime.env.example` at lowest priority: variables newly added in a new package get their defaults automatically, user edits are preserved
- `wait_for_healthy` reconciles against the expected service list from `docker compose config` and fails on restart-looping containers (previously a crash-looping service could be skipped and the install reported healthy)
- `load_docker_images` reconciles loaded images against the compose-expected list; any missing image aborts install with the exact image name
- Package manifest `fit2cloud/manifest.txt` (version/platform/build_time + md5 of image tars) generated at package time; `install.sh` verifies file presence by default and full md5 with `--verify-images`; `upgrade.sh` reconciles images the same way
- Docker images exported as a single `fit2cloud-images.tar` (shared base layers stored once — smaller package, one-shot `docker load`) plus an `images.list` inventory; export pre-checks that every image exists locally
- Image tag defaults to `<version>.<build_number>` instead of `master` (`-V/--image-version` to override), preventing accidental dev-tag packages; package filename no longer duplicates the tag
- `upgrade.sh` creates a pre-upgrade backup (conf/data/external-compose, taken after service stop for consistency), skippable with `--skip-backup`

### Fixed (deployment seams)
- `prepare.sh` no longer moves `fit2cloud/bin/fit2cloud/*` to the package root — that move broke the entry wrapper's relative-path resolution, left `INSTALL_DIR/bin/fit2cloud/standalone/` empty (systemd install silently skipped, f2cctl path in completion info nonexistent); the package root now ships an `install.sh` shim forwarding to `fit2cloud/scripts/install.sh`
- `install.sh` deploys `/usr/bin/f2cctl` as a path-baked shim and registers the systemd unit on fresh install; previously f2cctl was never deployed, and upgrade.sh copying it bare to `/usr/bin` resolved its internal `../../..` to `/scripts`
- `CE_ACCESS_IP` is auto-detected and written back before rendering (the template marks it `required`; the documented "leave empty to auto-detect" default previously failed rendering)
- Built-in MinIO credentials fixed: keys are generated before rendering and persisted to runtime.env/.env; `minio.env.tpl` defaults unified with `fit2cloud.properties.tpl` (the previous admin/Password123@minio vs fit2cloud/fit2cloud123 mismatch broke built-in MinIO auth)
- `set_env_value` rewritten with awk: GNU/BSD `sed -i` incompatibility broke it on macOS, and the escaping hack was fragile
- Package reproducibility: `dist/installer` and `cloud_plugins` are wiped on every build; `prepare.sh` strips runtime junk from the package (`.minio.sys`, logs, local install.env/runtime.env, `.DS_Store`)
- `f2cctl` reuses `service.sh:_get_compose_cmd` instead of a private duplicate
- Image pull retries up to 3 attempts per image before counting a failure

### Fixed
- Deploy mode unified to `CE_MODE=cluster`: `service.sh` now loads `ha-docker-compose.yml` and `fit2cloud.properties.tpl` now renders the Eureka cluster section for `cluster` (previously only `ha` did, so `cluster` users got a standalone template with EUREKA_SERVERS ignored)
- `ce-render-cfg`: output dir flag now registered as `-o` shorthand (was long-only `--o`, install-time rendering failed)
- `ce-render-cfg`: `required` accepts both `required .VAR` and `required "msg" .VAR`
- `kapacitor.conf.tpl`: Kapacitor runtime alert templates escaped so Go template parsing passes them through verbatim (render panicked before)
- `fit2cloud.properties.tpl`: missing newline between `rdb.password` and `rdb.pool.size`
- `package.sh`: `--env-file` option added (CLI options take priority); `-p/-d/-e` accept comma-separated lists
- `copy_middleware`/`copy_extensions`: multi-URL input was treated as a single item
- `install.sh`: existing `.env` is kept on re-install instead of overwritten; health-check timeout now configurable via `CE_HEALTHY_TIMEOUT` (default 600s) and fails the install instead of warning
- `pull-images.sh`: empty image list now errors instead of "succeeding"
- MinIO runtime metadata (`data/minio/.minio.sys/`) untracked and gitignored
- `-d /data` install dir normalized to `<dir>/fit2cloud` so compose volume paths (`CE_INSTALL_PATH/fit2cloud`) match the actual install location
- upgrade.sh re-merges `.env` from install.env/runtime.env so new default variables added by the new package are picked up

### Removed
- Legacy scripts: `install-new*.sh`, `install-silent.sh`, `utils.sh`
- `get_docker_compose_args()` from `docker.sh` — `get_compose_files()` in `service.sh` is sole authority
- `install_docker_compose()` (V1 standalone no longer auto-installed)
- Duplicate function definitions in `docker.sh` and `os.sh`
- Dead variables `INSTALL_MINIO`, `SKIP_MINIO`, `SKIP_TELEGRAF`
- `.mimocode` empty tracked file
