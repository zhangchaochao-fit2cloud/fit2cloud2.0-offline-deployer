#!/bin/bash
nginx_folder="/opt/nginx"
nginx_port="6680"
nginx_docker_image="registry.fit2cloud.com/public/nginx"

ARGS=`getopt -o hd:p: --long help,dir:,port: -- "$@"`
#if test $? != 0  ; then echo "Please input oss accesskey & secretkey..." >&2 ; exit 1 ; fi
eval set -- "$ARGS"
while true;do
	case "$1" in
	-d|--dir)
		nginx_folder="$2/nginx"
		shift 2
	;;
	-p|--port)
		nginx_port=$2
		shift 2
	;;
	-h|--help)
		echo "Usage: nginx-install.sh [OPTION]..."
		echo
		echo -e "  -d, --dir\tnginx workspace"
		echo -e "  -p, --port\tport"
		exit
	;;
	--)
		shift
		break
	;;
	*)
		echo "未知的属性:{$1}"
		exit 1
	;;
	esac
done

#docker环境检测
echo -ne "Docker 检测 ... "
hasDocker=`which docker 2>&1`
if [[ "${hasDocker}" =~ "no docker" ]]; then
  echo '[ERROR] 需要有 Docker 环境'
  exit 1
else
  dockerVersion=`docker info | grep 'Server Version' | awk -F: '{print $2}' | awk -F. '{print $1}'`
  if [ "$dockerVersion" -lt "18" ];then
    echo "[ERROR] Docker 版本需要 18 以上"
    exit 1
  else
    echo "[OK]"
  fi
fi 

echo "已有 nginx 镜像检测 ... "
nginx_image_count=`docker images | grep $nginx_docker_image | wc -l`
if [ "$nginx_image_count" -eq "0" ]; then
  echo "[OK]"
else
  echo "已有 nginx 镜像，请检查环境并手工配置"
  exit 1
fi

echo "加载 nginx 镜像 ... "
docker load -i nginx.tar
echo "完成"

echo -ne "创建 nginx 工作目录 ... "
mkdir -p "$nginx_folder/conf"
conf_path="$nginx_folder/conf/nginx.conf"
echo "完成"

echo -ne "创建 nginx 配置文件 ... "
cat <<EOF > $conf_path
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

    server {
        listen       80;
        server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;

        location / {
            #root   html;
            root   /opt/nginx/data;
	          autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
            index  index.html index.htm;
        }

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \.php$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \.php$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #    deny  all;
        #}
    }


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;

    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;

    #    ssl_session_cache    shared:SSL:1m;
    #    ssl_session_timeout  5m;

    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers  on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}
}
EOF
echo "完成"

echo "nginx 配置信息："
echo -e "  运行端口 - $nginx_port"
echo -e "  配置文件 - $conf_path"
echo -e "  日志目录 - $nginx_folder/logs"
echo -e "  文件目录 - $nginx_folder/data"

echo -ne "启动 nginx 服务 ... "
docker run  --name f2c-nginx -d -p $nginx_port:80 -v $conf_path:/etc/nginx/nginx.conf  -v $nginx_folder/logs:/var/log/nginx -v $nginx_folder/data:/opt/nginx/data $nginx_docker_image:latest
echo "启动完成"
