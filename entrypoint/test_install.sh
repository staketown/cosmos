#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="entrypoint-pubtest-2"
CHAIN_DENOM=""
BINARY_NAME="entrypointd"
BINARY_VERSION_TAG="v1.2.0"
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

wget -O ~/go/bin/entrypointd https://github.com/entrypoint-zone/testnets/releases/download/v1.2.0/entrypointd-1.2.0-linux-amd64
chmod +x ~/go/bin/entrypointd

entrypointd config keyring-backend os
entrypointd config chain-id $CHAIN_ID
entrypointd init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -s https://github.com/entrypoint-zone/testnets/blob/main/entrypoint-pubtest-2/genesis.json > $HOME/.entrypoint/config/genesis.json
# curl -s https://snapshots-testnet.stake-town.com/juno/addrbook.json > $HOME/.entrypoint/config/addrbook.json

CONFIG_TOML=$HOME/.entrypoint/config/config.toml
PEERS="81bf2ade773a30eccdfee58a041974461f1838d8@185.107.68.148:26656,d57c7572d58cb3043770f2c0ba412b35035233ad@80.64.208.169:26656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS=""
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.entrypoint/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.01ibc/8A138BC76D0FB2665F8937EC2BF01B9F6A714F6127221A0E155106A45E09BCC5"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.entrypoint/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"localhost:9090\"%address = \"localhost:$PORT_GRPC\"%; s%^address = \"localhost:9091\"%address = \"localhost:$PORT_GRPC_WEB\"%; s%^address = \"tcp://localhost:1317\"%address = \"tcp://localhost:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.entrypoint/cosmovisor/genesis/bin
mkdir -p ~/.entrypoint/cosmovisor/upgrades
cp ~/go/bin/entrypointd ~/.entrypoint/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/entrypointd.service > /dev/null << EOF
[Unit]
Description=Entrypoint Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=entrypointd"
Environment="DAEMON_HOME=$HOME/.entrypoint"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

entrypointd tendermint unsafe-reset-all --home $HOME/.entrypoint --keep-addr-book

# Add snapshot here
#URL="https://snapshots-testnet.stake-town.com/entrypoint/entrypoint-pubtest-2_latest.tar.lz4"
#curl -L $URL | lz4 -dc - | tar -xf - -C $HOME/.entrypoint
#[[ -f $HOME/.entrypoint/data/upgrade-info.json ]]  && cp $HOME/.entrypoint/data/upgrade-info.json $HOME/.entrypoint/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable entrypointd
sudo systemctl start entrypointd

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter