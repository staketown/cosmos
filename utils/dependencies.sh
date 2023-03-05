#!/bin/bash

echo "Installing dependencies..." && sleep 1
sudo apt-get update &&
sudo apt-get install -y curl iptables build-essential git lz4 wget jq make gcc nano chrony \
tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev &&

echo "Installing go..." && sleep 1
if ! [ -x "$(command -v go)" ]; then
  source <(curl -s "https://raw.githubusercontent.com/R1M-NODES/cosmos/master/utils/go_install.sh")
  source $HOME/.bash_profile
fi

echo "$(go version)"