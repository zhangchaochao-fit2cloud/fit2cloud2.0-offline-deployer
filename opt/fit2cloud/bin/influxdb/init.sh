#!/bin/bash

set -euo pipefail

echo 'init database and user ...'
influx <<EOF
create database fit2cloud;
create retention policy "rp_fit2cloud" on "fit2cloud" duration 180d replication 1 default;
create database kube_monitor;
create retention policy "rp_kube_monitor" on "kube_monitor" duration 30d replication 1 default;
create database os_monitor;
create retention policy "rp_os_monitor" on "os_monitor" duration 180d replication 1 default;
create database log_fit2cloud;
create retention policy "rp_log_fit2cloud" on "log_fit2cloud" duration 3d replication 1 default;
create user fit2cloud with PASSWORD '${INFLUXDB_PASSWORD}' WITH ALL PRIVILEGES;
EOF

auth_conf_num=$(grep -c 'auth-enabled' /etc/influxdb/influxdb.conf 2>/dev/null || echo 0)
if [[ "$auth_conf_num" -lt 1 ]]; then
    echo 'going to enable auth...'
    echo '[http]' >> /etc/influxdb/influxdb.conf
    echo '  auth-enabled = true' >> /etc/influxdb/influxdb.conf
    echo '  pprof-enabled = true' >> /etc/influxdb/influxdb.conf
    echo '  pprof-auth-enabled = true' >> /etc/influxdb/influxdb.conf
fi

influxd config /etc/influxdb/influxdb.conf
echo 'init database and user done!'
