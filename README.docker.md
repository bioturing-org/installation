## BioTuring System - GPU enterprise version installation guide
This edition of the installation guide describes the installation process of BioTuring&reg; System for container runtime (Docker/Containerd), K8S, and standalone Linux machine.

## 1. Introduction
BioTuring System is a GPU-accelerated single-cell and spatial platform developed by BioTuring&reg;. It dramatically increases the computing performance of single-cell and spatial analysis by harnessing the power of the graphics processing unit (GPU).
<br/>

### 1.1. Pre-Installation Requirements

Before installing the BioTuring System on Linux/K8S, some pre-installation steps are required:
- Container runtime (Docker, Containerd)
- The system has one or multiple NVIDIA GPU(s) (at least 16 GB memory per GPU)
- SSL certificate and a domain name for users to securely access the platform on the web browser
- A token obtained from BioTuring
- At least 64 GB of root partition.
- At least 32 GB of RAM
- At least 16 CPU cores. 
- Operating system:  Ubuntu 18.04.x, Ubuntu 20.04.x, Ubuntu 22.04.x, RHEL 7.x, RHEL 8.x, RHEL 9.x

### 1.2. Self-Signed CA Certificate installation (If you have problem with curl https):

Adding self-signed certificates as trusted to your proxy agent/server

```
bash ./cert/install.sh
```

## 2. Docker Installation:

We support container runtime: Docker, Containerd.

**Note**: The ideal system that we recommend for most companies is AWS [g5.8xlarge](https://aws.amazon.com/ec2/instance-types/g5/)

1. Simple installation (Recommended):
```
bash ./install.docker.sh
```

2. Manual Installation:

For GPU version

```
docker container run -d -t -i \
    -e WEB_DOMAIN='CHANGE THIS TO YOUR DOMAIN' \
    -e BIOTURING_TOKEN='USE TOKEN OBTAINED FROM BIOTURING' \
    -e ADMIN_USERNAME='admin' \
    -e ADMIN_PASSWORD='CHANGE YOUR PASSWORD IF NECESSARY' \
    -p 80:80 \
    -p 443:443 \
    -v '/path/to/persistent/storage/':/data/user_data \
    -v '/path/to/stateful/storage/':/data/app_data \
    -v '/path/to/ssl/storage/':/config/ssl \
    --gpus all \
    --link bioturing-ecosystem:latest \
    --name bioturing-ecosystem
```

For GPU version

```
docker container run -d -t -i \
    -e WEB_DOMAIN='CHANGE THIS TO YOUR DOMAIN' \
    -e BIOTURING_TOKEN='USE TOKEN OBTAINED FROM BIOTURING' \
    -e ADMIN_USERNAME='admin' \
    -e ADMIN_PASSWORD='CHANGE YOUR PASSWORD IF NECESSARY' \
    -p 80:80 \
    -p 443:443 \
    -v '/path/to/persistent/storage/':/data/user_data \
    -v '/path/to/stateful/storage/':/data/app_data \
    -v '/path/to/ssl/storage/':/config/ssl \
    --link bioturing-ecosystem-cpu:latest \
    --name bioturing-ecosystem-cpu
```

'/path/to/ssl/storage/' : must contain two files: tls.crt and tls.key

## 3. Notices

### 3.1. Security
- BioTuring System  uses HTTPS protocol to securely communicate over the network.
- All of the users need to authenticate using a BioTuring account or the company's SSO to access the platform.
- We highly recommend setting up a private VPC network for IP restriction.
- The data stays behind the company firewall.
- BioTuring System does not track any usage logs.

### 3.2. Data visibility
- Data can be uploaded to Personal Workspace or Data Sharing group.
- In the Personal Workspace, only the owner can see and manipulate the data she/he uploaded.
- In the Data Sharing group, only people in the group can see the data.
- In the Data Sharing group, only people with sufficient permissions can manipulate the data.
