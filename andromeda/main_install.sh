#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="andromeda-1"
CHAIN_DENOM="uandr"
BINARY_NAME="andromedad"
BINARY_VERSION_TAG="andromeda-1-v0.1.0"
CHEAT_SHEET="https://nodes.stake-town.com/andromeda"

printDelimiter
echo -e "Node moniker:       $NODE_MONIKER"
echo -e "Chain id:           $CHAIN_ID"
echo -e "Chain demon:        $CHAIN_DENOM"
echo -e "Binary version tag: $BINARY_VERSION_TAG"
printDelimiter && sleep 1

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/dependencies.sh)

echo "" && printGreen "Building binaries..." && sleep 1

cd $HOME || return
rm -rf andromedad
git clone https://github.com/andromedaprotocol/andromedad.git
cd andromedad || return
git checkout $BINARY_VERSION_TAG

make install

andromedad config keyring-backend os
andromedad config chain-id $CHAIN_ID
andromedad init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -s https://snapshots.stake-town.com/andromeda/genesis.json > $HOME/.andromeda/config/genesis.json
curl -s https://snapshots.stake-town.com/andromeda/addrbook.json > $HOME/.andromeda/config/addrbook.json

CONFIG_TOML=$HOME/.andromeda/config/config.toml
PEERS="e4c2267b90c7cfbb45090ab7647dc01df97f58f9@andromeda-m.peer.stavr.tech:4376,26cdc42778d24c8b0b0b68ed07c97685bfd8682f@178.162.165.65:26656,17dda7b03ce866dbe36c048282fb742dd895a489@95.56.244.244:56659,0f310196e29d1f289966141e22caa72afaea8060@seeds.cros-nest.com:46656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS=""
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.andromeda/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.0001uandr"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.andromeda/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"localhost:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.andromeda/cosmovisor/genesis/bin
mkdir -p ~/.andromeda/cosmovisor/upgrades
cp ~/go/bin/andromedad ~/.andromeda/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/andromedad.service > /dev/null << EOF
[Unit]
Description=Andromeda Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=andromedad"
Environment="DAEMON_HOME=$HOME/.andromeda"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

andromedad tendermint unsafe-reset-all --home $HOME/.andromeda --keep-addr-book

# Add snapshot here
URL="https://snapshots.stake-town.com/andromeda/andromeda-1_latest.tar.lz4"
curl -L $URL | lz4 -dc - | tar -xf - -C $HOME/.andromeda
[[ -f $HOME/.andromeda/data/upgrade-info.json ]] && cp $HOME/.andromeda/data/upgrade-info.json $HOME/.andromeda/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable andromedad
sudo systemctl start andromedad

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter