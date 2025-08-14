#!/bin/bash

ARGS=$(getopt -o ha:s:d:p:e:f:i: --long help,accesskey:,secretkey:,deployment-packages:,plugin-packages:,extension-packages:,platform:,image-address: -- "$@")
if test $? != 0  ; then echo "Please input oss accesskey & secretkey..." >&2 ; exit 1 ; fi
eval set -- "$ARGS"
while true;do
	case "$1" in
	-a|--accesskey)
		echo "-a | --accesskey"
		ak=$2
		shift 2
	;;
	-s|--secretkey)
		echo "-s | --accesskey"
		sk=$2
		shift 2
	;;
	-d|--deployment-packages)
		echo "-d | --deployment-packages"
		deployment_packages=($2)
		shift 2
	;;
	-p|--plugin-packages)
		echo "-p | --plugin-packages"
		plugin_packages=($2)
		shift 2
	;;
	-e|--extension-packages)
		echo "-e | --extension-packages"
		extension_packages=($2)
		shift 2
	;;
	-f|--platform)
		echo "-e | --platform"
        platform=${2:-"amd64"}
        all_platform=("amd64" "arm64")
        if [[ ! "${all_platform[*]}" =~ ${platform} ]]; then
          echo "未知的架构类型，仅支持：${all_platform[*]}"
          exit 1
        fi
		shift 2
	;;
	-i|--image-address)
		echo "-i | --image-address"
		IMAGE_ADDRESS=($2)
	;;
	-h|--help)
		echo "-h | --help"
		shift
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

function get_image_platform() {
    platform=${platform:-"amd64"}
    image_platform="linux/$platform"
    echo "镜像架构：${image_platform}"
}

get_image_platform

# step 1 - prepare fit2cloud2.0 config files
echo ''
echo ''
echo '******************************************************'
echo '* step 1 - prepare fit2cloud2.0 config files'
echo '******************************************************'
installer_folder=${WORKSPACE}'/installer'
# 不常用插件包
cloud_plugin_installer_folder=${WORKSPACE}'/cloud_plugins'
minio_docker_image="registry.fit2cloud.com/north/minio:latest"
IMAGE_ADDRESS=${IMAGE_ADDRESS:-"registry.fit2cloud.com/north"}
echo "IMAGE_ADDRESS=${IMAGE_ADDRESS}"
export IMAGE_ADDRESS
echo "IMAGE_ADDRESS=${IMAGE_ADDRESS}" >> ${WORKSPACE}/opt/fit2cloud/.env
# 解压AWS询价JSON
unzip -o opt/fit2cloud/conf/aws_price.json.zip -d opt/fit2cloud/conf/

# 镜像架构弱校验镜像（不用强制校验镜像架构，该镜像不是很必须的）
ARCH_WEAK_CHECK_IMAGES=("chrome")

rm -rf ${installer_folder}
mkdir -p ${installer_folder}
rm -rf ${cloud_plugin_installer_folder}
mkdir -p ${cloud_plugin_installer_folder}
if [ -d 'extensions' ];then
  mv extensions ${installer_folder}
fi
cp -rp ${WORKSPACE}/opt/* ${installer_folder}/
rm -rf ${installer_folder}/fit2cloud/data/mysql/*
mv ${installer_folder}/fit2cloud/bin/fit2cloud/* ${installer_folder}/
# copy conf files to templates
mkdir -p ${installer_folder}/fit2cloud/templates/conf
cp -rp ${installer_folder}/fit2cloud/docker-compose.yml ${installer_folder}/fit2cloud/templates/docker-compose.yml.template
conf_dir="${installer_folder}/fit2cloud/conf"
envsubst < ${installer_folder}/fit2cloud/docker-compose.yml > ${installer_folder}/fit2cloud/tmp-docker-compose.yml
envsubst < ${installer_folder}/fit2cloud/external-compose/base-docker-compose.yml >> ${installer_folder}/fit2cloud/tmp-docker-compose.yml
tmp_docker_compose_yml=${installer_folder}/fit2cloud/tmp-docker-compose.yml

for old_file_name in $(ls $conf_dir); do
    old_file="$conf_dir/$old_file_name"
    if [ ! -f $old_file ]; then
        continue
    fi
    new_file_name="$conf_dir/../templates/conf/${old_file_name}.template"
    cp $old_file $new_file_name
done

function get_config() {
  env_file=${WORKSPACE}/env
  param=$1
  value=$(sed -E '/^#.*|^ *$/d' $env_file | awk -F "${param}=" "/${param}=/{print \$2}" | tail -n1)
  echo $value
}


function convert_compose_label() {
    compose_file=${tmp_docker_compose_yml}
    images_label=( "$(get_config IMAGES)" )
    for image_label in ${images_label[*]}; do
      if [ "${platform}" == "arm64" ]; then
          image_tag=$(get_config "${image_label}_ARM64")
      else
          image_tag=$(get_config "${image_label}")
      fi
      format_image_tag=$(echo $image_tag | sed 's#\/#\\\/#g')
      echo "convert ----------> ${image_label} ${format_image_tag}"
      sed -i "s/${image_label}/${format_image_tag}/g" ${compose_file}
      #  docker pull "${image_tag}"
    done
}

function pull_platform_images() {
  convert_compose_label
  compose_file=${tmp_docker_compose_yml}
  image_names=$(cat ${compose_file} | grep image: | awk -F "image:" '{print $NF}')

  for image_name in ${image_names}; do
    echo "start pull image -----> ${image_platform} ${image_name}"
    docker pull --platform="${image_platform}" "${image_name}"

    image_arch=$(docker inspect "$image_name" | grep Arch)
    image_display_name=$(echo $image_name | awk -F "/" '{print $NF}' | awk -F ":" '{print $1}')
    if ! (echo "$image_arch" | grep -q "$platform") ; then
      if [[ ! "${ARCH_WEAK_CHECK_IMAGES[*]}" == *"$image_display_name"* ]]; then
        echo "Error 架构不存在, 当前镜像架构：${image_arch}，镜像名：${image_name}，请检查镜像是否存在 ${platform} 架构的镜像"
        exit 0
      fi
    fi
  done
}

function get_docker_install_package() {
    cd "${installer_folder}/fit2cloud/tools/" || exit 0
    DOCKER_PACKAGE_URL=$(get_config DOCKER_PACKAGE_URL)

    if [ "${platform}" == "arm64" ]; then
      DOCKER_PACKAGE_URL=$(get_config DOCKER_PACKAGE_URL_ARM64)
    fi

    docker_package="docker_${platform}.zip"
    wget -O "${docker_package}" "${DOCKER_PACKAGE_URL}"
    unzip "${docker_package}"
    rm -rf "${docker_package}"
    rm -rf __MACOSX

    # 2022-12-16 <jinli> [Feature #18697] 安装支持RHEL8
    DOCKER_PACKAGE_URL_RHEL8=$(get_config DOCKER_PACKAGE_URL_RHEL8)
    wget "${DOCKER_PACKAGE_URL_RHEL8}"
    tar -zxvf docker-rhel8.tar.gz
    rm -rf docker-rhel8.tar.gz
    cd "${installer_folder}"
}

function get_docker_install_package_from_local() {
    cd "${installer_folder}/fit2cloud/tools/" || exit 0
    docker_package="docker_${platform}.zip"
    if [ "${platform}" == "arm64" ]; then
      cp -f /opt/installer/fit2cloud/tools/docker/docker-arm64.zip ./${docker_package}
    else
      cp -f /opt/installer/fit2cloud/tools/docker/docker.zip ./${docker_package}
    fi
    unzip "${docker_package}"
    rm -rf "${docker_package}"
    rm -rf __MACOSX

    cp -f /opt/installer/fit2cloud/tools/docker/docker-rhel8.tar.gz ./docker-rhel8.tar.gz
    tar -zxvf docker-rhel8.tar.gz
    rm -rf docker-rhel8.tar.gz
    cd "${installer_folder}"
}

function get_minio_install_package() {
    if [ "${FROM_LOCAL}" == 'true' ]; then
      minio_docker_image="10.1.13.5/north/minio:latest"
      sed -i 's/minio_docker_image=.*/minio_docker_image="10.1.13.5\/north\/minio:latest"/' ${installer_folder}/fit2cloud/tools/minio/minio-install.sh
    fi
    docker pull --platform="${image_platform}" "$minio_docker_image"
    docker save -o minio.tar "$minio_docker_image"
    mv minio.tar fit2cloud/tools/minio/
}

function get_telegraf_package() {
    cd "${installer_folder}/fit2cloud/tools/telegraf"
    TELEGRAF_PACKAGE_URL=$(get_config TELEGRAF_PACKAGE_URL)
    curl -o telegraf-1.24.4-1.x86_64.rpm ${TELEGRAF_PACKAGE_URL}
}

function get_plugins() {
    if [ "a$plugin_packages" == 'a' ];then
        return 0
    fi
    echo 'Add plugins ...'
    for package in ${plugin_packages[@]};do
        local local_plugins=$(ls $package)
        for local_plugin in ${local_plugins[@]};do
            local f_local_plugin=$(echo "$local_plugin" | sed 's/-2.0-jar-with-dependencies.jar//')
            if [[ $plugins == '""' || $plugins == *"$f_local_plugin"* ]]; then
                cp -i "$package/$local_plugin" "${installer_folder}/fit2cloud/data/plugins"
                echo "$local_plugin"
            else
                cp -i "$package/$local_plugin" "${cloud_plugin_installer_folder}"
            fi
        done
    done
    echo 'Add plugins Done'
}

# step 2 - pull latest docker images
echo ''
echo ''
echo '******************************************************'
echo 'step 2 - pull latest docker images'
echo '******************************************************'
pull_platform_images
cd ${installer_folder}/fit2cloud
image_names=`cat ${tmp_docker_compose_yml} | grep image: | awk -F "image:" '{print $NF}'`
rm ${tmp_docker_compose_yml}

# step 3 - export docker images
echo ''
echo ''
echo '******************************************************'
echo '* step 3 - export docker images'
echo '******************************************************'
cd ${installer_folder}
mkdir docker-images
rm -f docker-images/*
cd docker-images

for image_name in ${image_names}; do
  name=$(echo ${image_name} | awk -F"/" '{ print $3 }')
  echo "start to export docker image : " ${name}
#  docker pull ${image_name}
  docker pull --platform="${image_platform}" "${image_name}"
  docker save -o ${name}.tar ${image_name}
  echo "success to export docker image : " ${name}
done

# step 4 - make installer file
echo ''
echo ''
echo '******************************************************'
echo '* step 4 - make installer file'
echo '******************************************************'

if [ "${FROM_LOCAL}" == 'true' ];then
  echo "FROM_LOCAL is true, copy package from local:/opt/installer/fit2cloud/tools"
  get_docker_install_package_from_local
else
  get_docker_install_package
fi

# download minio
get_minio_install_package

get_telegraf_package

get_plugins

mkdir -p fit2cloud/middleware_init
if [ "a$deployment_packages" != 'a' ];then
  cd ${installer_folder}/fit2cloud/
  # 判断middleware_init 是否存在，不存在则创建
  if [ ! -d middleware_init ];then
    echo 'middleware_init not exist, create it'
    mkdir middleware_init
  fi
  cd middleware_init
  echo 'Download Deployment Packages...'
  for package in ${deployment_packages[@]};do
    echo "downloading $package"
    wget -nv -O pkg.zip $package
    unzip -O utf8 -d ./middleware_init pkg.zip
    rm -f pkg.zip
  done
  echo 'Download All Deployment Packages Done'
fi

# download extensions
if [ "a$extension_packages" != 'a' ];then
  cd ${installer_folder}
  mkdir extensions
  cd extensions
  echo 'Download Extension Packages...'
  for package in ${extension_packages[@]};do
    echo "downloading $package"
    wget -nv $package
  done
  echo 'Download All Extension Packages Done'
fi


cd ${installer_folder}

curTime=`date "+%Y%m%d%H%M"`
m_version=${version}
if [ -z ${m_version} ];then
  echo "set m_version. version is %{version}，m_version is ${m_version}"
  m_version="V3.1.${BUILD_NUMBER}-release"
fi
buildId="${m_version} Build ${curTime}"
echo ${buildId} > ${installer_folder}/fit2cloud/conf/version
today=${today:-$(date "+%Y.%m.%d")}
fileName=cloudexplorer-${m_version}-${platform}-${today}
pluginFileName=cloudexplorer-cloudplugins-${m_version}-${platform}-${today}
fullFileName=${fileName}.tar.gz
fullPluginFileName=${pluginFileName}.tar.gz
md5FileName=${fileName}.md5
cd ..
tar zcvf ${fullFileName} installer
tar zcvf ${fullPluginFileName} -C $cloud_plugin_installer_folder .
md5sum ${fullFileName} | awk -F" " '{print "md5: "$1}' > ${md5FileName}

# step 5 - update offline installer to Aliyun OSS & clean temp files
echo ''
echo ''
echo '******************************************************'
echo '* step 5 - update offline installer to Aliyun OSS'
echo '******************************************************'
#java -jar /root/uploadToOss.jar $ak $sk fit2cloud2-offline-installer cmp/${md5FileName} ${installer_folder}/../${md5FileName}
#java -jar /root/uploadToOss.jar $ak $sk fit2cloud2-offline-installer cmp/${fullFileName} ${installer_folder}/../${fullFileName}
#rm -rf ${installer_folder}/../${md5FileName}
#rm -rf ${installer_folder}/../${fullFileName}