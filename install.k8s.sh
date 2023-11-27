#! /bin/bash

set -e

read -p "Your K8S engine [vanilla, microk8s]: " K8S_DIST

bash ./gpu/patch.driver.sh
if [ -z "$K8S_DIST" ] || [ "$K8S_DIST" != "microk8s" ]; then
    bash ./k8s/vanillak8s.install.sh
else
    bash ./k8s/microk8s.install.sh
fi