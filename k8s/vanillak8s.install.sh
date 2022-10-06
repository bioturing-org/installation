#! /bin/bash

set -e

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color

echo -e "${_BLUE}BioTuring ecosystem VanillaK8S installation version${_NC} ${_GREEN}stable${_NC}\n"

read -p "Please enter BioTuring TOKEN: " BBTOKEN
if [ -z "$BBTOKEN" ]; then
    echo -e "${_RED}Can not be empty${_NC}\n"
    exit 1
fi

read -p "Please enter your DOMAIN: " SVHOST
if [ -z "$SVHOST" ]; then
    echo -e "${_RED}Can not be empty${_NC}\n"
    exit 1
fi

read -p "Please enter your admin username (admin): " ADMIN_USERNAME
if [ -z "$ADMIN_USERNAME" ]; then
    ADMIN_USERNAME="admin"
fi

read -p "Please enter your admin password (turing2022): " ADMIN_PASSWORD
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="turing2022"
fi

read -p "Please enter BBrowserX's VERSION (latest): " BBVERSION
if [ -z "$BBVERSION" ]; then
    BBVERSION="latest"
fi

read -p "Please enter APP-DATA PVC's size (5Gi): " APPDATA_PVC_SIZE
if [ -z "$APPDATA_PVC_SIZE" ]; then
    APPDATA_PVC_SIZE="5Gi"
fi

read -p "Please enter USER-DATA PVC's size (5Gi): " USERDATA_PVC_SIZE
if [ -z "$USERDATA_PVC_SIZE" ]; then
    USERDATA_PVC_SIZE="5Gi"
fi

SSLCRT=""
SSLKEY=""
read -p "Use lets-encrypt SSL (your domain must be public), [y, n]: " USELETSENCRYPT
if [ -z "$USELETSENCRYPT" ] || [ "$USELETSENCRYPT" != "y" ]; then
    USELETSENCRYPT="false"

    read -p "Please enter SSL_CRT file: " CRT_PATH
    if [ -z "$CRT_PATH" ]; then
        echo -e "${_RED}Can not be empty${_NC}\n"
        exit 1
    fi
    
    if [[ -f $CRT_PATH ]]; then 
        SSLCRT=`base64 -w 0 ${CRT_PATH}`
    else
        echo -e "${_RED}Can not find: ${CRT_PATH}${_NC}\n"
        exit 1
    fi

    read -p "Please enter SSL_KEY file: " KEY_PATH
    if [ -z "$KEY_PATH" ]; then
        echo -e "${_RED}Can not be empty${_NC}\n"
        exit 1
    fi
    
    if [[ -f $CRT_PATH ]]; then 
        SSLKEY=`base64 -w 0 ${KEY_PATH}`
    else
        echo -e "${_RED}Can not find: ${KEY_PATH}${_NC}\n"
        exit 1
    fi
else
    USELETSENCRYPT="true"
fi

read -p "Please enter K8S namespace (default): " K8S_NAMESPACE
if [ -z "$K8S_NAMESPACE" ]; then
    K8S_NAMESPACE=""
fi

echo -e "${_BLUE}Enable GPU operator${_NC}\n"
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install --wait --generate-name nvidia/gpu-operator -n kube-system --set driver.enabled=false --set toolkit.enabled=false --debug

echo -e "${_BLUE}Add BioTuring Helm charts to K8S service${_NC}\n"
helm repo add bioturing https://bioturing.github.io/charts/apps/
helm repo update

echo -e "${_BLUE}Install BioTuring system to K8S service${_NC}\n"
if [ "$USELETSENCRYPT" == "true" ]; then
    if [ -z "$K8S_NAMESPACE" ]; then
        helm upgrade --install --set secret.data.bbtoken="${BBTOKEN}" \
            --set secret.data.domain="${SVHOST}" \
            --set secret.server.useletsencrypt="${USELETSENCRYPT}" \
            --set secret.admin.username="${ADMIN_USERNAME}" \
            --set secret.admin.password="${ADMIN_PASSWORD}" \
            --set persistence.dirs.user.size="${USERDATA_PVC_SIZE}" \
            --set persistence.dirs.app.size="${APPDATA_PVC_SIZE}" \
            bioturing bioturing/ecosystem --version ${BBVERSION}
    else
        helm upgrade --install --set secret.data.bbtoken="${BBTOKEN}" \
            --set secret.data.domain="${SVHOST}" \
            --set secret.server.useletsencrypt="${USELETSENCRYPT}" \
            --set secret.admin.username="${ADMIN_USERNAME}" \
            --set secret.admin.password="${ADMIN_PASSWORD}" \
            --set persistence.dirs.user.size="${USERDATA_PVC_SIZE}" \
            --set persistence.dirs.app.size="${APPDATA_PVC_SIZE}" \
            --namespace ${K8S_NAMESPACE} \
            bioturing bioturing/ecosystem --version ${BBVERSION} \
            --create-namespace
    fi
else
    if [ -z "$K8S_NAMESPACE" ]; then
        helm upgrade --install --set secret.data.bbtoken="${BBTOKEN}" \
            --set secret.data.domain="${SVHOST}" \
            --set secret.server.certificate="${SSLCRT}" \
            --set secret.server.key="${SSLKEY}" \
            --set secret.server.useletsencrypt="${USELETSENCRYPT}" \
            --set secret.admin.username="${ADMIN_USERNAME}" \
            --set secret.admin.password="${ADMIN_PASSWORD}" \
            --set persistence.dirs.user.size="${USERDATA_PVC_SIZE}" \
            --set persistence.dirs.app.size="${APPDATA_PVC_SIZE}" \
            bioturing bioturing/ecosystem --version ${BBVERSION}
    else
        helm upgrade --install --set secret.data.bbtoken="${BBTOKEN}" \
            --set secret.data.domain="${SVHOST}" \
            --set secret.server.certificate="${SSLCRT}" \
            --set secret.server.key="${SSLKEY}" \
            --set secret.server.useletsencrypt="${USELETSENCRYPT}" \
            --set secret.admin.username="${ADMIN_USERNAME}" \
            --set secret.admin.password="${ADMIN_PASSWORD}" \
            --set persistence.dirs.user.size="${USERDATA_PVC_SIZE}" \
            --set persistence.dirs.app.size="${APPDATA_PVC_SIZE}" \
            --namespace ${K8S_NAMESPACE} \
            bioturing bioturing/ecosystem --version ${BBVERSION} \
            --create-namespace
    fi
fi
