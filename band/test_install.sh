#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="band-v3-testnet-1"
CHAIN_DENOM="uband"
BINARY_NAME="bandd"
BINARY_VERSION_TAG="v3.0.0-rc2"
CHEAT_SHEET=""

printDelimiter
echo -e "Node moniker:       $NODE_MONIKER"
echo -e "Chain id:           $CHAIN_ID"
echo -e "Chain demon:        $CHAIN_DENOM"
echo -e "Binary version tag: $BINARY_VERSION_TAG"
printDelimiter && sleep 1

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/dependencies.sh)

echo "" && printGreen "Building binaries..." && sleep 1

cd $HOME || return
rm -rf chain
git clone https://github.com/bandprotocol/chain.git
cd chain || return
git checkout $BINARY_VERSION_TAG

make install

bandd config set client keyring-backend os
bandd config set client chain-id $CHAIN_ID
bandd init "$NODE_MONIKER" --chain-id $CHAIN_ID

# Download genesis and addrbook
curl -s https://raw.githubusercontent.com/bandprotocol/launch/master/band-v3-testnet-1/genesis.json >$HOME/.band/config/genesis.json
#curl -s https://snapshots-testnet.stake-town.com/prysm/addrbook.json > $HOME/.band/config/addrbook.json

CONFIG_TOML=$HOME/.band/config/config.toml
PEERS=""
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS="cf91ef30a9877d7cf0e654d5f75f8d68ff6ee4e7@34.2.133.3:26656,cbe055146a4607c3db5909bfa20e9e0c5ea95f90@35.212.1.35:26656"
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.band/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
sed -E -i "s/timeout_commit = \".*\"/timeout_commit = \"500ms\"/" $CONFIG_TOML
sed -E -i "s/timeout_propose = \".*\"/timeout_propose = \"1.5s\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.0025uband"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.band/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML &&
  sed -i.bak -e "s%^address = \"localhost:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML &&
  sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.band/cosmovisor/genesis/bin
mkdir -p ~/.band/cosmovisor/upgrades
cp ~/go/bin/bandd $HOME/.band/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/bandd.service >/dev/null <<EOF
[Unit]
Description=Band Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=bandd"
Environment="DAEMON_HOME=$HOME/.band"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

bandd tendermint unsafe-reset-all --home $HOME/.band --keep-addr-book

# Add snapshot here
URL="https://snapshots-testnet.stake-town.com/prysm/prysm-devnet-1_latest.tar.lz4"
curl -L $URL | lz4 -dc - | tar -xf - -C $HOME/.band
[[ -f $HOME/.band/data/upgrade-info.json ]] && cp $HOME/.band/data/upgrade-info.json $HOME/.band/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-bandd
sudo systemctl enable bandd
sudo systemctl start bandd

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printDelimiter
