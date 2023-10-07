#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="entangle_33133-1"
CHAIN_DENOM="aNGL"
BINARY_NAME="entangled"
BINARY_VERSION_TAG="v1.0.1"
CHEAT_SHEET="https://nodes.stake-town.com/elys"

printDelimiter
echo -e "Node moniker:       $NODE_MONIKER"
echo -e "Chain id:           $CHAIN_ID"
echo -e "Chain demon:        $CHAIN_DENOM"
echo -e "Binary version tag: $BINARY_VERSION_TAG"
printDelimiter && sleep 1

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/dependencies.sh)

echo "" && printGreen "Building binaries..." && sleep 1

cd $HOME || return
rm -rf entangle-blockchain
git clone https://github.com/Entangle-Protocol/entangle-blockchain.git
cd entangle-blockchain || return
# git checkout $BINARY_VERSION_TAG

make install

$BINARY_NAME config keyring-backend os
$BINARY_NAME config chain-id $CHAIN_ID
$BINARY_NAME init "$NODE_MONIKER" --chain-id $CHAIN_ID

cp -f config/genesis.json $HOME/.entangled/config/
cp -f config/config.toml $HOME/.entangled/config/

#curl -s https://snapshots-testnet.stake-town.com/elys/genesis.json > $HOME/.elys/config/genesis.json
#curl -s https://snapshots-testnet.stake-town.com/elys/addrbook.json > $HOME/.elys/config/addrbook.json

CONFIG_TOML=$HOME/.entangled/config/config.toml
PEERS="b651ea2a0517e82c1a476e25966ab3de3159afe8@34.229.22.39:26656,3b389873f999763d3f937f63f765f0948411e296@44.192.85.92:26656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS=""
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.entangled/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.0001aNGL"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.entangled/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.entangled/cosmovisor/genesis/bin
mkdir -p ~/.entangled/cosmovisor/upgrades
cp ~/go/bin/$BINARY_NAME $HOME/.entangled/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/entangled.service > /dev/null << EOF
[Unit]
Description=Entangled Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=entangled"
Environment="DAEMON_HOME=$HOME/.entangled"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

$BINARY_NAME tendermint unsafe-reset-all --home $HOME/.entangled --keep-addr-book

# Add snapshot here
#URL="https://snapshots-testnet.stake-town.com/elys/elystestnet-1_latest.tar.lz4"
#curl $URL | lz4 -dc - | tar -xf - -C $HOME/.entangled
#[[ -f $HOME/.entangled/data/upgrade-info.json ]] && cp $HOME/.entangled/data/upgrade-info.json $HOME/.entangled/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable $BINARY_NAME
sudo systemctl start $BINARY_NAME

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter