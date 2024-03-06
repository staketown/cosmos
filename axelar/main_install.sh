#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="axelar-dojo-1"
CHAIN_DENOM="uaxl"
BINARY_NAME="axelard"
BINARY_VERSION_TAG="v0.35.5"
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
rm -rf axelar-core
git clone https://github.com/axelarnetwork/axelar-core.git
cd axelar-core || return
git checkout $BINARY_VERSION_TAG

make install

axelard config keyring-backend os
axelard config chain-id $CHAIN_ID
axelard init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -Ls https://snapshots.kjnodes.com/axelar/genesis.json > $HOME/.axelar/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/axelar/addrbook.json > $HOME/.axelar/config/addrbook.json
#curl -s https://snapshots-testnet.stake-town.com/andromeda/genesis.json > $HOME/.andromedad/config/genesis.json
#curl -s https://snapshots-testnet.stake-town.com/andromeda/addrbook.json > $HOME/.andromedad/config/addrbook.json

CONFIG_TOML=$HOME/.axelar/config/config.toml
PEERS=""
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS="400f3d9e30b69e78a7fb891f60d76fa3c73f0ecc@axelar.rpc.kjnodes.com:16559"
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.axelar/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.007$CHAIN_DENOM\"/" $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.axelar/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.axelar/cosmovisor/genesis/bin
mkdir -p ~/.axelar/cosmovisor/upgrades
cp ~/go/bin/axelard ~/.axelar/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/axelard.service > /dev/null << EOF
[Unit]
Description=Axelar Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=axelard"
Environment="DAEMON_HOME=$HOME/.axelar"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

axelard tendermint unsafe-reset-all --home $HOME/.axelar --keep-addr-book

# Add snapshot here
curl -L https://snapshots.kjnodes.com/axelar/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.axelar
[[ -f $HOME/.axelar/data/upgrade-info.json ]] && cp $HOME/.axelar/data/upgrade-info.json $HOME/.axelar/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable axelard
sudo systemctl start axelard

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter