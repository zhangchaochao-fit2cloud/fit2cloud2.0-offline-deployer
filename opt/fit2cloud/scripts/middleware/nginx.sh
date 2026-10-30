#!/bin/bash
# 库文件：被入口脚本 source 引入；错误处理(set -euo pipefail)由入口统一提供，勿在此单独添加

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common.sh"

mw_init

check_nginx() {
    local install_nginx=$(get_env_value CE_INSTALL_NGINX "false" "$ENV_FILE")
    if [[ "$install_nginx" != "true" ]]; then
        return 0
    fi

    if cmd_exists nginx; then
        log_info "Nginx: 已安装"
        log_ok
        return 0
    else
        log_info "Nginx: 未安装"
        return 1
    fi
}

install_nginx() {
    local install_nginx=$(get_env_value CE_INSTALL_NGINX "false" "$ENV_FILE")
    if [[ "$install_nginx" != "true" ]]; then
        log_info "Nginx: 跳过安装"
        return 0
    fi

    if cmd_exists nginx; then
        log_info "Nginx: 已安装，跳过"
        return 0
    fi

    print_subtitle "安装 Nginx..."

    if cmd_exists yum; then
        yum install -y nginx
    elif cmd_exists apt-get; then
        apt-get update -y && apt-get install -y nginx
    else
        log_error "无法自动安装 Nginx，请手动安装"
        return 1
    fi

    systemctl enable nginx
    log_success "Nginx 安装完成"
}

generate_self_signed_cert() {
    local cert_dir="$1"
    local cert_file="$cert_dir/fit2cloud.crt"
    local key_file="$cert_dir/fit2cloud.key"

    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        log_info "自签名证书已存在，跳过生成"
        return 0
    fi

    ensure_dir "$cert_dir"

    log_info "生成自签名证书..."

    if cmd_exists openssl; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/C=CN/ST=Beijing/L=Beijing/O=Fit2Cloud/CN=fit2cloud" \
            2>/dev/null
    else
        log_error "openssl 未安装，无法生成自签名证书"
        return 1
    fi

    chmod 600 "$key_file"
    log_success "自签名证书生成完成: $cert_file"
}

generate_letsencrypt_cert() {
    local domain="$1"
    local email="$2"
    local cert_dir="/etc/nginx/ssl/letsencrypt"

    if [[ -f "$cert_dir/live/$domain/fullchain.pem" ]]; then
        log_info "Let's Encrypt 证书已存在，跳过生成"
        return 0
    fi

    if ! cmd_exists certbot; then
        log_info "安装 certbot..."
        if cmd_exists yum; then
            yum install -y epel-release
            yum install -y certbot python3-certbot-nginx
        elif cmd_exists apt-get; then
            apt-get update -y
            apt-get install -y certbot python3-certbot-nginx
        else
            log_error "无法自动安装 certbot，请手动安装"
            return 1
        fi
    fi

    log_info "申请 Let's Encrypt 证书..."

    if certbot certonly --nginx \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        2>/dev/null; then
        log_success "Let's Encrypt 证书申请完成"
        return 0
    else
        log_error "Let's Encrypt 证书申请失败"
        return 1
    fi
}

configure_nginx() {
    local install_nginx=$(get_env_value CE_INSTALL_NGINX "false" "$ENV_FILE")
    if [[ "$install_nginx" != "true" ]]; then
        return 0
    fi

    print_subtitle "配置 Nginx..."

    local access_port=$(get_env_value CE_ACCESS_PORT "80" "$ENV_FILE")
    local gateway_port="6601"
    local ssl_enabled=$(get_env_value CE_NGINX_SSL "false" "$ENV_FILE")
    local ssl_cert=$(get_env_value CE_NGINX_SSL_CERT "" "$ENV_FILE")
    local ssl_key=$(get_env_value CE_NGINX_SSL_KEY "" "$ENV_FILE")
    local ssl_auto_generate=$(get_env_value CE_NGINX_SSL_AUTO_GENERATE "false" "$ENV_FILE")
    local ssl_auto_type=$(get_env_value CE_NGINX_SSL_AUTO_TYPE "self-signed" "$ENV_FILE")
    local ssl_domain=$(get_env_value CE_NGINX_SSL_DOMAIN "" "$ENV_FILE")
    local ssl_email=$(get_env_value CE_NGINX_SSL_EMAIL "" "$ENV_FILE")
    local http_to_https=$(get_env_value CE_NGINX_HTTP_TO_HTTPS "false" "$ENV_FILE")
    local gzip_enabled=$(get_env_value CE_NGINX_GZIP "true" "$ENV_FILE")
    local gzip_types=$(get_env_value CE_NGINX_GZIP_TYPES "text/plain text/css application/json application/javascript text/xml application/xml" "$ENV_FILE")
    local static_cache=$(get_env_value CE_NGINX_STATIC_CACHE "true" "$ENV_FILE")
    local static_cache_days=$(get_env_value CE_NGINX_STATIC_CACHE_DAYS "30" "$ENV_FILE")
    local security_headers=$(get_env_value CE_NGINX_SECURITY_HEADERS "true" "$ENV_FILE")
    local rate_limit=$(get_env_value CE_NGINX_RATE_LIMIT "false" "$ENV_FILE")
    local rate_limit_rps=$(get_env_value CE_NGINX_RATE_LIMIT_RPS "10" "$ENV_FILE")
    local rate_limit_burst=$(get_env_value CE_NGINX_RATE_LIMIT_BURST "20" "$ENV_FILE")
    local ip_allow=$(get_env_value CE_NGINX_IP_ALLOW "" "$ENV_FILE")
    local ip_deny=$(get_env_value CE_NGINX_IP_DENY "" "$ENV_FILE")
    local custom_conf=$(get_env_value CE_NGINX_CUSTOM_CONF "" "$ENV_FILE")

    local nginx_conf_dir="/etc/nginx/conf.d"
    local ssl_cert_dir="/etc/nginx/ssl"
    ensure_dir "$nginx_conf_dir"

    local ssl_port=443
    if [[ "$ssl_enabled" == "true" ]]; then
        if [[ "$ssl_auto_generate" == "true" ]]; then
            if [[ "$ssl_auto_type" == "self-signed" ]]; then
                generate_self_signed_cert "$ssl_cert_dir"
                ssl_cert="$ssl_cert_dir/fit2cloud.crt"
                ssl_key="$ssl_cert_dir/fit2cloud.key"
            elif [[ "$ssl_auto_type" == "letsencrypt" ]]; then
                if [[ -z "$ssl_domain" ]]; then
                    log_error "Let's Encrypt 需要配置 CE_NGINX_SSL_DOMAIN"
                    return 1
                fi
                if [[ -z "$ssl_email" ]]; then
                    log_error "Let's Encrypt 需要配置 CE_NGINX_SSL_EMAIL"
                    return 1
                fi
                generate_letsencrypt_cert "$ssl_domain" "$ssl_email"
                ssl_cert="/etc/letsencrypt/live/$ssl_domain/fullchain.pem"
                ssl_key="/etc/letsencrypt/live/$ssl_domain/privkey.pem"
            fi
        else
            if [[ -z "$ssl_cert" || ! -f "$ssl_cert" ]]; then
                log_error "SSL 证书文件不存在: $ssl_cert"
                return 1
            fi
            if [[ -z "$ssl_key" || ! -f "$ssl_key" ]]; then
                log_error "SSL 私钥文件不存在: $ssl_key"
                return 1
            fi
        fi
    fi

    cat > "$nginx_conf_dir/fit2cloud.conf" << EOF
# Fit2Cloud Nginx 配置 - 由安装脚本自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

EOF

    if [[ "$rate_limit" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
# 限流配置
limit_req_zone \$binary_remote_addr zone=fit2cloud:10m rate=${rate_limit_rps}r/s;

EOF
    fi

    if [[ "$ip_allow" != "" || "$ip_deny" != "" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
# IP 访问控制
EOF
        if [[ "$ip_deny" != "" ]]; then
            for ip in $(echo "$ip_deny" | tr ',' ' '); do
                echo "deny $ip;" >> "$nginx_conf_dir/fit2cloud.conf"
            done
        fi
        if [[ "$ip_allow" != "" ]]; then
            for ip in $(echo "$ip_allow" | tr ',' ' '); do
                echo "allow $ip;" >> "$nginx_conf_dir/fit2cloud.conf"
            done
            echo "deny all;" >> "$nginx_conf_dir/fit2cloud.conf"
        fi
        echo "" >> "$nginx_conf_dir/fit2cloud.conf"
    fi

    if [[ "$http_to_https" == "true" && "$ssl_enabled" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
# HTTP 重定向到 HTTPS
server {
    listen ${access_port};
    server_name _;
    return 301 https://\$host\$request_uri;
}

EOF
    fi

    cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
server {
EOF

    if [[ "$ssl_enabled" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    listen ${ssl_port} ssl http2;
    ssl_certificate ${ssl_cert};
    ssl_certificate_key ${ssl_key};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

EOF
    else
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    listen ${access_port};

EOF
    fi

    cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    server_name _;

    client_max_body_size 0;

EOF

    if [[ "$security_headers" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF
        if [[ "$ssl_enabled" == "true" ]]; then
            cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
EOF
        fi
        echo "" >> "$nginx_conf_dir/fit2cloud.conf"
    fi

    if [[ "$gzip_enabled" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types ${gzip_types};

EOF
    fi

    if [[ "$static_cache" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires ${static_cache_days}d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

EOF
    fi

    if [[ "$rate_limit" == "true" ]]; then
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    # 限流
    location / {
        limit_req zone=fit2cloud burst=${rate_limit_burst} nodelay;
        proxy_pass http://127.0.0.1:${gateway_port};
EOF
    else
        cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
    location / {
        proxy_pass http://127.0.0.1:${gateway_port};
EOF
    fi

    cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300;
        proxy_read_timeout 300;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
EOF

    if [[ "$custom_conf" != "" && -f "$custom_conf" ]]; then
        echo "" >> "$nginx_conf_dir/fit2cloud.conf"
        echo "# 自定义配置" >> "$nginx_conf_dir/fit2cloud.conf"
        cat "$custom_conf" >> "$nginx_conf_dir/fit2cloud.conf"
    fi

    cat >> "$nginx_conf_dir/fit2cloud.conf" << EOF
}
EOF

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        if [[ "$ssl_enabled" == "true" ]]; then
            log_success "Nginx 配置完成 (HTTPS 端口 $ssl_port → $gateway_port)"
        else
            log_success "Nginx 配置完成 (端口 $access_port → $gateway_port)"
        fi
    else
        log_error "Nginx 配置语法错误，请检查 $nginx_conf_dir/fit2cloud.conf"
        return 1
    fi
}
