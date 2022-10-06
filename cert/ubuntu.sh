#! /bin/bash

set -e

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color

# Basic package
echo -e "${_BLUE}Installing base package${_NC}\n"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install build-essential wget curl ca-certificates -y

# Cert
echo -e "${_BLUE}Installing trusted SSL certificates${_NC}\n"
for filename in ./cert/files/*.crt; do
    cat "$filename" >> "./cert/files/bbrowserx.crt"
done
sudo mkdir -p /usr/local/share/ca-certificates/
sudo mv ./cert/files/bbrowserx.crt /usr/local/share/ca-certificates/
sudo chmod +x /usr/local/share/ca-certificates/bbrowserx.crt
sudo update-ca-certificates
