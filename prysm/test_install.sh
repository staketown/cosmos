#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="prysm-devnet-1"
CHAIN_DENOM="uprysm"
BINARY_NAME="prysmd"
BINARY_VERSION_TAG="v0.1.0-devnet"
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
rm -rf prysm
git clone https://github.com/kleomedes/prysm.git
cd prysm || return
git checkout $BINARY_VERSION_TAG

make install

prysmd config keyring-backend os
prysmd config chain-id $CHAIN_ID
prysmd init "$NODE_MONIKER" --chain-id $CHAIN_ID

# Download genesis and addrbook
curl -s https://snapshots-testnet.stake-town.com/prysm/genesis.json > $HOME/.prysm/config/genesis.json
curl -s https://snapshots-testnet.stake-town.com/prysm/addrbook.json > $HOME/.prysm/config/addrbook.json

CONFIG_TOML=$HOME/.prysm/config/config.toml
PEERS="69509925a520c5c7c5f505ec4cedab95073388e5@136.243.13.36:29856,bc1a37c7656e6f869a01bb8dabaf9ca58fe61b0c@5.9.73.170:29856,b377fd0b14816eef8e12644340845c127d1e7d93@79.13.87.34:26656,c80143f844fd8da4f76a0a43de86936f72372168@184.107.57.137:18656,afc7a20c15bde738e68781238307f4481938109d@94.130.35.120:18656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS=""
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.prysm/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.0uprysm"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.prysm/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"localhost:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.prysm/cosmovisor/genesis/bin
mkdir -p ~/.prysm/cosmovisor/upgrades
cp ~/go/bin/prysmd $HOME/.prysm/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/prysmd.service > /dev/null << EOF
[Unit]
Description=Prysm Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=prysmd"
Environment="DAEMON_HOME=$HOME/.prysm"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

prysmd tendermint unsafe-reset-all --home $HOME/.prysm --keep-addr-book

# Add snapshot here
URL="https://snapshots-testnet.stake-town.com/prysm/prysm-devnet-1_latest.tar.lz4"
curl -L $URL | lz4 -dc - | tar -xf - -C $HOME/.prysm
[[ -f $HOME/.prysm/data/upgrade-info.json ]] && cp $HOME/.prysm/data/upgrade-info.json $HOME/.prysm/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable prysmd
sudo systemctl start prysmd

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printDelimiter