#! /bin/bash

set -e


_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color

# Basic package
echo -e "${_BLUE}Installing base package${_NC}\n"
sudo yum update -y
sudo yum groupinstall 'Development Tools'
sudo yum install curl wget ca-certificates -y

# Cert
echo -e "${_BLUE}Installing trusted SSL certificates${_NC}\n"
for filename in ./cert/files/*.crt; do
    cat "$filename" >> "./cert/files/bbrowserx.crt"
done
sudo mkdir -p /etc/pki/ca-trust/source/anchors
sudo mv ./cert/files/bbrowserx.crt /etc/pki/ca-trust/source/anchors/
sudo chmod +x /etc/pki/ca-trust/source/anchors/bbrowserx.crt
sudo update-ca-trust