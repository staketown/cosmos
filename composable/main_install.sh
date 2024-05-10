#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="centauri-1"
CHAIN_DENOM="ppica"
BINARY_NAME="picad"
BINARY_VERSION_TAG="v6.6.41"
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
rm -rf composable-centauri
git clone https://github.com/notional-labs/composable-centauri.git
cd $HOME/composable-centauri || return
git checkout $BINARY_VERSION_TAG

make install

picad config keyring-backend file
picad config chain-id $CHAIN_ID
picad init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -s https://snapshots.stake-town.com/composable/genesis.json > $HOME/.banksy/config/genesis.json
curl -s https://snapshots.stake-town.com/composable/addrbook.json > $HOME/.banksy/config/addrbook.json

CONFIG_TOML=$HOME/.banksy/config/config.toml
PEERS="4cb008db9c8ae2eb5c751006b977d6910e990c5d@65.108.71.163:2630,63559b939442512ed82d2ded46d02ab1021ea29a@95.214.55.138:53656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS="c7f52f81ee1b1f7107fc78ca2de476c730e00be9@65.109.80.150:2635"
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.banksy/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0ppica"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.banksy/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"localhost:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.banksy/cosmovisor/genesis/bin
mkdir -p ~/.banksy/cosmovisor/upgrades
cp ~/go/bin/picad $HOME/.banksy/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/picad.service > /dev/null << EOF
[Unit]
Description=Picasso Node
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/.banksy
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=picad"
Environment="DAEMON_HOME=$HOME/.banksy"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

picad tendermint unsafe-reset-all --home $HOME/.banksy --keep-addr-book

# Add snapshot here
URL="https://snapshots.stake-town.com/composable/centauri-1_latest.tar.lz4"
curl $URL | lz4 -dc - | tar -xf - -C $HOME/.banksy
[[ -f $HOME/.banksy/data/upgrade-info.json ]] && cp $HOME/.banksy/data/upgrade-info.json $HOME/.banksy/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable picad
sudo systemctl start picad

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter