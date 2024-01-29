#! /bin/bash
# REDHAT OS

set -e

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color
_MINIMUM_ROOT_SIZE=64424509440 # 60GB
DT=`date "+%Y-%m-%d-%H%M%S"`

# Default Parameter
CONTAINER_NAME="bioturing-ecosystem"

# Default folders 
DEFAULT_USER_DATA_VOLUME="/bioturing_ecosystem/user_data"
DEFAULT_APP_DATA_VOLUME="/bioturing_ecosystem/app_data"
DEFAULT_SSL_VOLUME="/config/ssl"
DEFAULT_SCRIPT_LOG_VOLUME="/bioturing_ecosystem/script_log"

# Passing parameter storage file
PARAMETER_CONFIG_FILE=$DEFAULT_APP_DATA_VOLUME/t2d_parameter_config_$DT

function to_int {
    local -i num="10#${1}"
    echo "${num}"
}

function port_is_ok {
    local port="$1"
    local -i port_num=$(to_int "${port}" 2>/dev/null)

    if (( $port_num < 1 || $port_num > 65535 )) ; then
        echo "*** ${port} is not a valid port" 1>&2
        return
    fi

    echo 'ok'
}

function ssl_fun {
    read -p "ssl volume /config/ssl (this directory must contain two files: tls.crt and tls.key from your SSL certificate for HTTPS): " SSL_VOLUME

    if [ -z "$SSL_VOLUME" ];
    then
        SSL_VOLUME=${DEFAULT_SSL_VOLUME}
        echo -e "${_BLUE}SSL Storage location : $SSL_VOLUME${_NC}\n"
    fi

    if [ ! -d "$SSL_VOLUME" ];
    then
        echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
        exit 1
    fi

    NO_OF_FILE=`ls ${SSL_VOLUME}/tls* | wc -l`
        if [[ $NO_OF_FILE -ne 2 ]]
            then
            ls -lrt $SSL_VOLUME
            echo -e "${_RED}tls files DOES NOT exist. Exiting...${_NC}"
            exit 1
        else
            echo -e "${_BLUE}listing SSL files${_NC}\n"
            ls -lrt $SSL_VOLUME
        fi
}

echo -e "${_BLUE}BioTuring ecosystem RHEL installation version${_NC} ${_GREEN}stable${_NC}\n"

# Input user data volume
echo -e "\n"
read -p "user_data volume (persistent volume to store user data : /bioturing_ecosystem/user_data): " USER_DATA_VOLUME
if [ -z "$USER_DATA_VOLUME" ];
then
    USER_DATA_VOLUME=${DEFAULT_USER_DATA_VOLUME}
fi

if [ ! -d "$USER_DATA_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
else
    echo -e "${_BLUE}User data storage : $USER_DATA_VOLUME${_NC}\n"
fi

# Input app data volume
echo -e "\n"
read -p "app_data volume (this is the place to store the binary files of all services : /bioturing_ecosystem/app_data): " APP_DATA_VOLUME
if [ -z "$APP_DATA_VOLUME" ];
then
    APP_DATA_VOLUME=${DEFAULT_APP_DATA_VOLUME}
fi

if [ ! -d "$APP_DATA_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
else
    echo -e "${_BLUE}Application data storage : $APP_DATA_VOLUME${_NC}\n"
fi

# Input log volume
echo -e "\n"
read -p "script log volume (this is the place to store script execution log : /bioturing_ecosystem/script_log): " SCRIPT_LOG_VOLUME
if [ -z "$SCRIPT_LOG_VOLUME" ];
then
    SCRIPT_LOG_VOLUME=${DEFAULT_SCRIPT_LOG_VOLUME}
fi

if [ ! -d "$SCRIPT_LOG_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
else
    echo -e "${_BLUE}Script execution log storage : $SCRIPT_LOG_VOLUME${_NC}\n"
fi

# Input BioTuring Token
echo -e "\n"
read -p "BioTuring token (please contact support@bioturing.com for a token): " BIOTURING_TOKEN
if [ -z "$BIOTURING_TOKEN" ];
then
    echo -e "${_RED}Empty token is not allowed. Exiting...${_NC}"
    exit 1
fi

# Input Base URL
echo -e "\n"
read -p "Base URL (example: bioturing.com): " BASE_URL
if [ -z "$BASE_URL" ];
then
    echo -e "${_RED}Empty domain name is not allowed. Exiting...${_NC}"
    exit 1
fi

# Input HTTP_PROXY , HTTPS_PROXY AND NO_PROXY
echo -e "\n"
read -p "HTTP_PROXY: " HTTP_PROXY
if [ -z "$HTTP_PROXY" ];
then
    HTTP_PROXY=""
fi

echo -e "\n"
read -p "HTTPS_PROXY: " HTTPS_PROXY
if [ -z "$HTTPS_PROXY" ];
then
    HTTPS_PROXY=""
fi

echo -e "\n"
echo -e "${_RED}If you are using NO_PROXY : Make sure 0.0.0.0,Your Domain name,localhost,127.0.0.0 also added.${_NC}"
read -p "NO_PROXY: " NO_PROXY
if [ -z "$NO_PROXY" ];
then
    NO_PROXY=""
fi

# /dev/shm confirmation.
T_MEM=`free -g | grep Mem: | awk -F " " '{ print $2}'`

if [[ $T_MEM -eq 0 ]]
then
    echo -e "\n"
    echo -e "${_RED}Sorry physical memory is not enough to install BBROWSERX. Exiting...${_NC}"
    echo -e "${_RED}Total memory in GB $T_MEM. Exiting...${_NC}"
    exit 1
else
    echo -e "\n"
    echo -e "${_BLUE}Total memory in GB $T_MEM${_NC}\n"
    echo -e "${_BLUE}Kindly allocate shared memory that would be 1/2 of total memory.${_NC}\n"
    echo -e "${_BLUE}SHM SIZE : $(( $T_MEM / 2 )) ${_NC}"

fi

FSTAB_ENTRY_CK=`cat /etc/fstab | grep -i shm | wc -l`

if [[ $FSTAB_ENTRY_CK -eq 0 ]]
then
    echo -e "\n"
    echo -e "${_GREEN}Current /etc/fstab file contents.${_NC}\n"
    cat /etc/fstab
    echo -e "\n"
    echo -e "${_BLUE}Kindly put entry below to /etc/fstab file.${_NC}\n"
    echo -e "${_RED}tmpfs /dev/shm tmpfs defaults,size=$(( $T_MEM / 2 ))g 0 0${_NC}\n"
    echo -e "${_BLUE}Kindly execute command below before start execution script again.${_NC}\n"
    echo -e "${_RED}sudo mount -o remount /dev/shm${_NC}\n"
    echo -e "${_RED}/dev/shm is missing with /etc/fstab file. Exiting...${_NC}\n"
    exit 1
fi

# Input shm size
echo -e "\n"
read -p "shm size (please input shm size. This value is half of physical memory that we did for /dev/shm : $(( $T_MEM / 2 )) ): " shm_size
if [ -z "$shm_size" ];
then
    echo -e "${_RED}Empty shm_size is not allowed. Exiting...${_NC}"
    exit 1
else
    shm_sizep="${shm_size}gb"
    echo -e "${_RED}shm_size is : $shm_sizep ${_NC}"
fi

echo -e "\n"
echo -e "${_RED}If you are using Nginx or any proxy kindly do not use port 80, If already in the service. ${_NC}\n"
echo -e "${_RED}If you are using Load balancer, please make sure HTTP port forwarding or HTTP port should be allow from LB.${_NC}\n"
    read -p "Please input expose HTTP port (80): " HTTP_PORT
    if [ -z "$HTTP_PORT" ]; then
        HTTP_PORT=80
        echo -e "${_BLUE}HTTP port : ${HTTP_PORT}${_NC}"
    fi

    HTTP_PORT_VALID=`port_is_ok ${HTTP_PORT}`
    if [ "$HTTP_PORT_VALID" == "ok" ]; then
        echo -e "${_BLUE}HTTP port is OK${_NC}\n"
    else
        echo -e "${_RED}Invalid expose HTTP port: ${HTTP_PORT}${_NC}\n"
        exit 1
    fi

# Input SSL volume
echo -e "\n"
read -p "Would you like to configure SSL [y/n] : " SSL_CONFIRM
echo -e "\n"
if [ -z "$SSL_CONFIRM" ] || [ "$SSL_CONFIRM" != "y" ]; then
    echo -e "${_BLUE}Kindly configure SSL with your Proxy / Loadblancer.${_NC}"
else
    SSL_CONFIRM="y"
    echo -e "\n"
    read -p "Please input expose HTTPS port (443): " HTTPS_PORT
    if [ -z "$HTTPS_PORT" ]; then
        HTTPS_PORT=443
        echo -e "${_BLUE}HTTPS port : ${HTTPS_PORT}${_NC}"
    fi

    HTTPS_PORT_VALID=`port_is_ok ${HTTPS_PORT}`
    if [ "$HTTPS_PORT_VALID" == "ok" ]; then
        echo -e "${_BLUE}HTTPS port is OK${_NC}\n"
    else
        echo -e "${_RED}Invalid expose HTTPS port: ${HTTPS_PORT}${_NC}\n"
        exit 1
    fi
    # ssl information
    echo -e "${_BLUE}SSL Verification.${_NC}"
    # Call SSL config function.
    ssl_fun
fi

# Input SSO Domain
echo -e "\n"
read -p "SSO DOMAIN (example: @bioturing.com). Kindly use a comma separator passing multiple domains: " VALIDATION_STRING
if [ -z "$VALIDATION_STRING" ];
then
    VALIDATION_STRING="*"
    echo -e "${_BLUE}SSO ALLOWED DOMAINS : ${VALIDATION_STRING}${_NC}"
else
    echo -e "${_BLUE}SSO ALLOWED DOMAINS : ${VALIDATION_STRING}${_NC}"
fi

# Worker Count
echo -e "\n"
read -p "WORKER COUNT : Min 4 : " N_TQ_WORKERS
if [ -z "$N_TQ_WORKERS" ];
then
    N_TQ_WORKERS="4"
    echo -e "${_GREEN}Minimum worker count set to 4${_NC}"
fi

# Basic package
echo -e "${_BLUE}Installing base package${_NC}\n"
sudo yum update -y
sudo yum groupinstall 'Development Tools'

# Cert
read -p "Install Self-Signed CA Certificate [y, n]: " AGREE_CA
if [ -z "$AGREE_CA" ] || [ "$AGREE_CA" != "y" ]; then
    sudo yum install curl wget ca-certificates -y
else
    sudo yum install curl wget ca-certificates -y
    echo -e "${_BLUE}Installing trusted SSL certificates${_NC}\n"
    sudo bash ./cert/rhel.sh
fi

#------------
# Docker installation confirmation.
ALREADY_INSTALL_COUNT=`pidof dockerd | wc -l`

echo "Docker count : $ALREADY_INSTALL_COUNT"

if [ $ALREADY_INSTALL_COUNT -gt 0 ]
then
    echo -e "${_BLUE}Docker is already installed with this server.${_NC}\n"
    docker version
else

# Docker
echo -e "${_BLUE}Installing docker${_NC}\n"
RHEL_VERSION=$(uname -r | sed 's/^.*\(el[0-9]\+\).*$/\1/')
if [ "$RHEL_VERSION" == "el7" ];
then
    sudo cat >> /etc/yum.repos.d/docker-ce.repo << EOF
        [centos-extras]
        name=Centos extras - $basearch
        baseurl=http://mirror.centos.org/centos/7/extras/x86_64
        enabled=1
        gpgcheck=1
        gpgkey=http://centos.org/keys/RPM-GPG-KEY-CentOS-7
EOF
    sudo yum install -y slirp4netns fuse-overlayfs container-selinux
fi
sudo yum install -y yum-utils
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
fi

# Check for Nvidia driver and show detail
COUNT_DRIVER=`ls /proc/driver/ | grep -i nvidia | wc -l`

if [ $COUNT_DRIVER -ge 1 ]
then
    echo -e "\nNvidia driver detected."
    nvidia-smi
else
    echo -e "\nNvidia driver is not detecting.\n"
    read -p "Do you need to install CUDA Toolkit [y, n]: " AGREE_INSTALL
    if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
        echo -e "${_RED}Ignore re-install CUDA Toolkit${_NC}"
    else
        echo -e "${_BLUE}Checking root partition capacity${_NC}"
        ROOT_SIZE=$(df -B1 --output=source,size --total / | grep 'total' | awk '{print $2}')
        if [ "$ROOT_SIZE" -lt "$_MINIMUM_ROOT_SIZE" ];
        then
            echo -e "${_RED}The root partition should be at least 64GB${_NC}"
            exit 1
        fi

        # NVIDIA CUDA Toolkit
        echo -e "\n"
        echo -e "${_BLUE}Installing NVIDIA CUDA Toolkit 11.7${_NC}\n"
        wget https://developer.download.nvidia.com/compute/cuda/11.7.1/local_installers/cuda_11.7.1_515.65.01_linux.run
        sudo sh cuda_11.7.1_515.65.01_linux.run --no-drm || true
        sleep 120s;
        # Check for Nvidia driver and show detail
        COUNT_DRIVER=`ls /proc/driver/ | grep -i nvidia | wc -l`
        nvidia-smi
        result=$?

        if [ $COUNT_DRIVER -ge 1 ] || [ $result -eq 0 ]; then
            echo "Cuda driver installation succeed."
            nvidia-smi
        else
            echo "Cuda driver installation failed."
            echo "Please visit site below and install cuda driver manually."
            echo "https://developer.nvidia.com/cuda-downloads"
            exit 1
        fi
    fi
fi

read -p "Do you need to install NVIDIA Docker 2 [y, n]: " AGREE_INSTALL
if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
    echo -e "${_RED}Ignore re-install NVIDIA Docker 2${_NC}"
else
    # NVIDIA CUDA Docker 2
    echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
    #distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
    #&& curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    #sudo yum clean expire-cache
    #sudo yum install -y nvidia-docker2
    #sudo systemctl restart docker
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    #sudo yum-config-manager --enable nvidia-container-toolkit-experimental
    sudo yum install -y nvidia-container-toolkit
    sudo systemctl restart docker
fi

# Check Version
echo -e "\n"
read -p "Please enter BBrowserX's VERSION (latest) 2.1.0: " BBVERSION
if [ -z "$BBVERSION" ]; then
    BBVERSION="2.1.0"
fi

# Paramter config file updates
echo "# Parameters that used during script execution." > ${PARAMETER_CONFIG_FILE}
echo "N_TQ_WORKERS=${N_TQ_WORKERS}" >> ${PARAMETER_CONFIG_FILE}
echo "CONTAINER_NAME=bioturing-ecosystem" >> ${PARAMETER_CONFIG_FILE}
echo "USER_DATA_VOLUME=${USER_DATA_VOLUME}" >> ${PARAMETER_CONFIG_FILE}
echo "APP_DATA_VOLUME=${APP_DATA_VOLUME}" >> ${PARAMETER_CONFIG_FILE}
echo "BIOTURING_TOKEN=${BIOTURING_TOKEN}" >> ${PARAMETER_CONFIG_FILE}
echo "BASE_URL=${BASE_URL}" >> ${PARAMETER_CONFIG_FILE}
echo "HTTP_PROXY=${HTTP_PROXY}" >> ${PARAMETER_CONFIG_FILE}
echo "HTTPS_PROXY=${HTTPS_PROXY}" >> ${PARAMETER_CONFIG_FILE}
echo "NO_PROXY=${NO_PROXY}" >> ${PARAMETER_CONFIG_FILE}
echo "TOTAL MEMORY=${T_MEM}" >> ${PARAMETER_CONFIG_FILE}
echo "SSL_CONFIRM=${SSL_CONFIRM}" >> ${PARAMETER_CONFIG_FILE}
echo "SSL_VOLUME=${SSL_VOLUME}" >> ${PARAMETER_CONFIG_FILE}
echo "HTTP_PORT=${HTTP_PORT}" >> ${PARAMETER_CONFIG_FILE}
echo "HTTPS_PORT=${HTTPS_PORT}" >> ${PARAMETER_CONFIG_FILE}
echo "VALIDATION_STRING=${VALIDATION_STRING}" >> ${PARAMETER_CONFIG_FILE}
echo "AGREE_CA=${AGREE_CA}" >> ${PARAMETER_CONFIG_FILE}
echo "ROOT_SIZE=${ROOT_SIZE}" >> ${PARAMETER_CONFIG_FILE}
echo "BBVERSION=${BBVERSION}" >> ${PARAMETER_CONFIG_FILE}

echo "FSTAB file entries" >> ${PARAMETER_CONFIG_FILE}
cat /etc/fstab >>  ${PARAMETER_CONFIG_FILE}

# Stop already running container.
echo -e "\n"
echo "checking docker for running container";
DOCKER_NAME=`docker ps --filter "name=$CONTAINER_NAME" --format "{{.ID}}-{{.Names}}"`

if [ -z "$DOCKER_NAME" ]; then
    echo -e "\n"
    echo "$CONTAINER_NAME not running, nothing to stop";
else
    echo -e "\n"
    echo "stopping $CONTAINER_NAME"
    sudo docker stop $CONTAINER_NAME || true
    echo -e "\n"
    echo "removing $CONTAINER_NAME"
    sudo docker rm $CONTAINER_NAME || true
fi

# Define log file name
TALK2DATA_LOG=$SCRIPT_LOG_VOLUME/t2d_logs_$DT

echo "Talk2Data -- Script execution log : ${TALK2DATA_LOG}"

# Log in to registry.bioturing.com
echo -e "\n"
echo "Running Talk2Data " > ${TALK2DATA_LOG}
echo -e "\n"
echo "Start: `date`" >> ${TALK2DATA_LOG}
echo -e "\n"
echo "-----------------------------------------------------------------" >> ${TALK2DATA_LOG}
echo -e "\n"

# Pull BioTuring ecosystem
echo -e "${_BLUE}Pulling bioturing ecosystem image${_NC}"
if [ "$SSL_CONFIRM" == "yes" ]  || [ "$SSL_CONFIRM" == "y" ]; then
    echo -e "${_BLUE} SSL CONFIRMED.${_NC}\n"
        docker pull bioturing/bioturing-ecosystem:${BBVERSION}
        docker run -t -i \
        -e BASE_URL="$BASE_URL" \
        -e BIOTURING_TOKEN="$BIOTURING_TOKEN" \
        -e VALIDATION_STRINGS="$VALIDATION_STRING" \
        -e HTTP_PROXY="$HTTP_PROXY" \
        -e HTTPS_PROXY="$HTTPS_PROXY" \
        -e NO_PROXY="$NO_PROXY" \
        -e N_TQ_WORKERS="$N_TQ_WORKERS" \
        -p ${HTTP_PORT}:80 \
        -p ${HTTPS_PORT}:443 \
        -v "$APP_DATA_VOLUME":/data/app_data \
        -v "$USER_DATA_VOLUME":/data/user_data \
        -v "$SSL_VOLUME":/config/ssl \
        --name bioturing-ecosystem \
        --shm-size=${shm_sizep} \
        --gpus all \
        -d \
        --restart always \
        bioturing/bioturing-ecosystem:${BBVERSION} 2>&1  | tee -a ${TALK2DATA_LOG}
else
    echo -e "${_RED}NO SSL${_NC}\n"
        docker pull bioturing/bioturing-ecosystem:${BBVERSION}
        docker run -t -i \
        -e BASE_URL="$BASE_URL" \
        -e BIOTURING_TOKEN="$BIOTURING_TOKEN" \
        -e VALIDATION_STRINGS="$VALIDATION_STRING" \
        -e HTTP_PROXY="$HTTP_PROXY" \
        -e HTTPS_PROXY="$HTTPS_PROXY" \
        -e NO_PROXY="$NO_PROXY" \
        -e N_TQ_WORKERS="$N_TQ_WORKERS" \
        -p ${HTTP_PORT}:3000 \
        -v "$APP_DATA_VOLUME":/data/app_data \
        -v "$USER_DATA_VOLUME":/data/user_data \
        --name bioturing-ecosystem \
        --shm-size=${shm_sizep} \
        --gpus all \
        -d \
        --restart always \
        bioturing/bioturing-ecosystem:${BBVERSION} 2>&1  | tee -a ${TALK2DATA_LOG}
fi

echo -e "\n"
echo "Started and UP and Running ...Talk2Data " >> ${TALK2DATA_LOG}
echo -e "\n"
echo "`date`" >> ${TALK2DATA_LOG}
echo -e "\n"
echo "-----------------------------------------------------------------" >> ${TALK2DATA_LOG}

echo -e "\n"
echo -e "${_BLUE}BioTuring ecosystem instance status : ${_NC}\n"
docker ps -a