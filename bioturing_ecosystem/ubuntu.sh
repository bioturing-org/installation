#! /bin/bash
# Ubuntu OS

set -e

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color
_MINIMUM_ROOT_SIZE=64424509440 # 60GB
DT=`date "+%Y-%m-%d-%H%M%S"`

echo -e "${_BLUE}BioTuring ecosystem UBUNTU installation version${_NC} ${_GREEN}stable${_NC}\n"

# /dev/shm confirmation and setup
T_MEM=$(free -g | awk '/Mem:/ {print $2}')

if [[ $T_MEM -eq 0 ]]; then
    echo -e "\n${_RED}Sorry, physical memory is not enough to install BBROWSERX. Exiting...${_NC}"
    echo -e "${_RED}Total memory in GB: $T_MEM${_NC}"
    exit 1
else
    echo -e "\n${_BLUE}Total memory in GB: $T_MEM${_NC}"
fi

# Automatically select shm size = 50% of total RAM
SHM_SIZE_GB=$(( T_MEM / 2 ))
shm_size="${SHM_SIZE_GB}gb"  # This will be used in --shm-size later
echo -e "${_BLUE}Auto-selected SHM size: $shm_size${_NC}"

# Generate shm entry string
SHM_ENTRY="tmpfs /dev/shm tmpfs defaults,size=${SHM_SIZE_GB}g 0 0"

# show fstab entry

fstab_entry_display()
{
    echo -e "${_GREEN}fstab entry detail${_NC}\n"
    echo -e "${_GREEN}=====================${_NC}\n"
    cat /etc/fstab
}

# Check if /etc/fstab already contains /dev/shm entry
if grep -qE "^[^#]*[[:space:]]+/dev/shm[[:space:]]+" /etc/fstab; then
    echo -e "${_GREEN}/dev/shm entry already exists in /etc/fstab. Skipping addition.${_NC}\n"
    fstab_entry_display
else
    echo -e "${_YELLOW}/dev/shm entry not found in /etc/fstab. Adding it now...${_NC}"

    # Backup fstab first
    sudo cp /etc/fstab /etc/fstab.bak

    # Append only if entry is truly new
    if ! grep -qF "$SHM_ENTRY" /etc/fstab; then
        echo "$SHM_ENTRY" | sudo tee -a /etc/fstab > /dev/null
        echo -e "${_GREEN}Entry added to /etc/fstab:${_NC}"
        echo -e "${_BLUE}$SHM_ENTRY${_NC}"
        fstab_entry_display
    else
        echo -e "${_YELLOW}Entry already exists with exact string. No changes made.${_NC}"
        fstab_entry_display
    fi

    # Remount /dev/shm
    echo -e "${_BLUE}Remounting /dev/shm...${_NC}"
    sudo mount -o remount /dev/shm

    echo -e "${_GREEN}/dev/shm successfully remounted with updated size.${_NC}\n"
fi

echo -e "\n"
read -p "Do you want to update & upgrade base packages? [y/n]: " AGREE_UPDATE
echo -e "\n"

if [[ "$AGREE_UPDATE" == "y" || "$AGREE_UPDATE" == "Y" ]]; then
    echo -e "${_BLUE}Installing base packages...${_NC}\n"
    sudo apt-get update
    sudo apt-get upgrade -y
else
    echo -e "${_GREEN}Skipped base package update & upgrade.${_NC}\n"
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
    curl https://get.docker.com | sh
    sudo systemctl --now enable docker
    sudo systemctl start docker
fi


# Verify require  tool
REQUIRED_TOOLS=("gcc" "g++" "make")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${_YELLOW}$tool is not installed. Installing build-essential...${_NC}"
        sudo apt-get update
        sudo apt-get install -y build-essential
        break
    fi
    echo -e "${_GREEN}$tool already installed${_NC}"

done

# Check for Nvidia driver and show detail
COUNT_DRIVER=`ls /proc/driver/ | grep -i nvidia | wc -l`

if [ $COUNT_DRIVER -ge 1 ]
then
    echo -e "\nNvidia driver detected."
    nvidia-smi
else
    echo -e "\nNvidia driver is not detecting."
    echo -e "\n"
    read -p "Do you need install CUDA Toolkit [y, n]: " AGREE_INSTALL
    if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
        echo -e "${_RED}Ignore install CUDA Toolkit${_NC}"
    else

        # NVIDIA CUDA Toolkit
        # Check if the CUDA installer file exists

        if [ ! -f cuda_12.4.0_550.54.14_linux.run ]; then
            echo -e "${_BLUE}Downloading NVIDIA CUDA Toolkit 12.4.0${_NC}\n"
            wget https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_550.54.14_linux.run
        else
            echo -e "${_BLUE}CUDA installer already exists. Skipping download.${_NC}\n"
        fi

        echo -e "${_BLUE}Installation CUDA Toolkit 12.4.0 started...${_NC}\n"
        echo -e "${_BLUE}Please wait for a while...${_NC}\n"

        sudo sh cuda_12.4.0_550.54.14_linux.run
        sleep 120s

        # Check for Nvidia driver and show detail
        COUNT_DRIVER=`ls /proc/driver/ | grep -i nvidia | wc -l`
        nvidia-smi
        result=$?

        if [ $COUNT_DRIVER -ge 1 ] || [ $result -eq 0 ]; then
            echo "Cuda driver installation succeed."
        else
            echo "Cuda driver installation failed."
            echo "Please visit site below and install cuda driver manually."
            echo "https://developer.nvidia.com/cuda-downloads"
            exit 1
        fi
    fi
fi

    read -p "Do you need install NVIDIA Docker 2 [y, n]: " AGREE_INSTALL
    if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
        echo -e "${_RED}Ignore re-install NVIDIA Docker 2${_NC}"
    else
        # NVIDIA CUDA Docker 2
        echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
        echo -e "${_BLUE}Reference : https://runs-on.com/blog/3-how-to-setup-docker-with-nvidia-gpu-support-on-ubuntu-22${_NC}\n"
        echo -e "${_BLUE}Reference : https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installing-with-yum-or-dnf${_NC}\n"
        echo -e "${_BLUE}Reference : https://github.com/NVIDIA/nvidia-docker/issues/1268${_NC}\n"

        distribution=$(. /etc/os-release;echo $ID$VERSION_ID) &&\
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&\
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        sudo apt-get update
        sudo apt-get install -y nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
    fi

        echo -e "${_BLUE}Checking root partition capacity${_NC}"
        ROOT_SIZE=$(df -B1 --output=source,size --total / | grep 'total' | awk '{print $2}')
        if [ "$ROOT_SIZE" -lt "$_MINIMUM_ROOT_SIZE" ];
        then
            echo -e "${_RED}The root partition should be at least 64GB${_NC}"
            exit 1
        fi


    # NVIDIA Sets the compute mode to Default mode
    echo -e "${_BLUE}NVIDIA Sets the compute mode to Default mode, allowing multiple processes to share the GPU.${_NC}\n"
    nvidia-smi -c 0 || true

    # Enables Persistence Mode for the NVIDIA driver.
    echo -e "${_BLUE}Enables Persistence Mode for the NVIDIA driver${_NC}\n"
    nvidia-smi -pm 1 || true

# Copy bioturing_ecosystem.env to /etc/docker/
# Change env file
mkdir -p /etc/docker

if cp -f ./bioturing_ecosystem/bioturing_ecosystem.env /etc/docker/bioturing_ecosystem.env; then
    echo -e "${_GREEN}Environment file copied successfully to /etc/docker/bioturing_ecosystem.env${_NC}"
else
    echo -e "${_RED}Failed to copy environment file. Exiting...${_NC}"
    exit 1
fi

echo -e "${_BLUE}Using env file at: /etc/docker/bioturing_ecosystem.env${_NC}"

# === Clear old environment and load fresh ===
echo -e "${_BLUE}Loading environment variables from env file...${_NC}"

# Unset previous values
unset CONTAINER_NAME BASE_URL BIOTURING_TOKEN VALIDATION_STRING
unset HTTP_PROXY HTTPS_PROXY NO_PROXY
unset N_TQ_WORKERS BBVERSION
unset APP_DATA_VOLUME USER_DATA_VOLUME DATABASE_VOLUME SSL_VOLUME
unset HTTP_PORT HTTPS_PORT

# Source the new values
if [ -f /etc/docker/bioturing_ecosystem.env ]; then
    set -a
    source /etc/docker/bioturing_ecosystem.env
    set +a
    echo -e "${_GREEN}Environment variables loaded successfully.${_NC}"
else
    echo -e "${_RED}ERROR: Environment file not found at /etc/docker/bioturing_ecosystem.env. Exiting.${_NC}"
    exit 1
fi


# Stop already running container.
echo -e "\n"

echo "checking docker for running container";
DOCKER_NAME=`docker ps --filter "name=$CONTAINER_NAME"`

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

# Pull BioTuring ecosystem
echo -e "${_BLUE}Pulling bioturing ecosystem image${_NC}"

        docker pull bioturing/bioturing-ecosystem12:${BBVERSION}
        docker run -t -i \
        --env-file /etc/docker/bioturing_ecosystem.env \
        -p ${HTTP_PORT}:80 \
        -p ${HTTPS_PORT}:443 \
        -v "$APP_DATA_VOLUME":/data/app_data \
        -v "$USER_DATA_VOLUME":/data/user_data \
        -v "$USER_DATA_VOLUME":/home/shared \
        -v "$DATABASE_VOLUME":/database \
        -v "$SSL_VOLUME":/config/ssl \
        --name "$CONTAINER_NAME" \
        --cap-add SYS_ADMIN \
        --device /dev/fuse \
        --security-opt apparmor:unconfined \
        --shm-size=${shm_size} \
        --gpus all \
        -d \
        --privileged --restart always \
        bioturing/bioturing-ecosystem12:${BBVERSION}

echo "-----------------------------------------------------------------"

echo -e "\n"
echo -e "${_BLUE}BioTuring ecosystem instance status : ${_NC}\n"
docker ps -a