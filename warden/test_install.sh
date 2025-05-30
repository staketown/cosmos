#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="chiado_10010-1"
CHAIN_DENOM="award"
BINARY_NAME="wardend"
BINARY_VERSION_TAG="v0.6.2"
CHEAT_SHEET=""

printDelimiter
echo -e "Node moniker:       $NODE_MONIKER"
echo -e "Chain id:           $CHAIN_ID"
echo -e "Chain demon:        $CHAIN_DENOM"
echo -e "Binary version tag: $BINARY_VERSION_TAG"
printDelimiter && sleep 1

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/dependencies.sh)

echo "" && printGreen "Building binaries..." && sleep 1

cd $HOME
wget -O ~/go/bin/wardend https://github.com/warden-protocol/wardenprotocol/releases/download/v0.6.2/wardend-0.6.2-linux-amd64
chmod +x ~/go/bin/wardend

wardend version

wardend config set client keyring-backend os
wardend config set client chain-id "$CHAIN_ID"
wardend init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -Ls https://snapshots-testnet.stake-town.com/warden/genesis.json > $HOME/.warden/config/genesis.json
curl -Ls https://snapshots-testnet.stake-town.com/warden/addrbook.json > $HOME/.warden/config/addrbook.json

CONFIG_TOML=$HOME/.warden/config/config.toml
PEERS=""
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS="2d2c7af1c2d28408f437aef3d034087f40b85401@52.51.132.79:26656"
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.warden/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "250000000000000award"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.warden/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML
sed -i.bak -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%; s%^address = \"127.0.0.1:8545\"%address = \"0.0.0.0:$PORT_EVM_RPC\"%; s%^ws-address = \"127.0.0.1:8546\"%ws-address = \"0.0.0.0:$PORT_EVM_WS\"%; s%^metrics-address = \"127.0.0.1:6065\"%metrics-address = \"0.0.0.0:$PORT_EVM_METRICS\"%" $APP_TOML
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.warden/cosmovisor/genesis/bin
mkdir -p ~/.warden/cosmovisor/upgrades
cp ~/go/bin/wardend ~/.warden/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/wardend.service > /dev/null << EOF
[Unit]
Description=Warden Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=wardend"
Environment="DAEMON_HOME=$HOME/.warden"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

wardend tendermint unsafe-reset-all --home $HOME/.warden --keep-addr-book

# Add snapshot here
URL="https://snapshots-testnet.stake-town.com/warden/chiado_10010-1_latest.tar.lz4"
curl -L $URL | lz4 -dc - | tar -xf - -C $HOME/.warden
[[ -f $HOME/.warden/data/upgrade-info.json ]]  && cp $HOME/.warden/data/upgrade-info.json $HOME/.warden/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable wardend
sudo systemctl start wardend

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter