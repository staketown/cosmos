#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/R1M-NODES/cosmos/master/utils/common.sh)

printLogo

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="ojo-devnet"
CHAIN_DENOM="uojo"
BINARY_NAME="ojod"
BINARY_VERSION_TAG="v0.1.2"
CHEAT_SHEET=""

printDelimiter
echo -e "Node moniker:       $NODE_MONIKER"
echo -e "Chain id:           $CHAIN_ID"
echo -e "Chain demon:        $CHAIN_DENOM"
echo -e "Binary version tag: $BINARY_VERSION_TAG"
printDelimiter && sleep 1

source <(curl -s https://raw.githubusercontent.com/R1M-NODES/cosmos/master/utils/dependencies.sh)

echo "Building binaries..." && sleep 1

cd $HOME || return
rm -rf ojo
git clone https://github.com/ojo-network/ojo.git
cd $HOME/ojo || return
git checkout ${BINARY_VERSION_TAG}
make install
ojod version # v0.1.2

ojod config keyring-backend test
ojod config chain-id $CHAIN_ID
ojod init "$NODE_MONIKER" --chain-id $CHAIN_ID

# Download genesis and addrbook
curl -Ls https://snapshots.kjnodes.com/ojo-testnet/genesis.json > $HOME/.ojod/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/ojo-testnet/addrbook.json > $HOME/.ojod/config/addrbook.json

CONFIG_TOML=$HOME/.ojod/config/config.toml
PEERS=""
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS="3f472746f46493309650e5a033076689996c8881@ojo-testnet.rpc.kjnodes.com:50659"
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.ojod/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "1000"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "10"|g' $APP_TOML
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):36656\"/" $CONFIG_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^snapshot-interval *=.*|snapshot-interval = 1000|g' $APP_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.000025uojo"|g' $APP_TOML

# Custom ports
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:36658\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:36657\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:7060\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:36656\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":36660\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:10090\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:10091\"%; s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:2317\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:36657\"%" $HOME/.ojod/config/client.toml

echo "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/ojod.service > /dev/null << EOF
[Unit]
Description=Ojo Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which ojod) start
Restart=on-failure
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF

ojod tendermint unsafe-reset-all --home $HOME/.ojod --keep-addr-book

# Add snapshot here
curl -L https://snapshots.kjnodes.com/ojo-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.ojod

sudo systemctl daemon-reload
sudo systemctl enable ojod
sudo systemctl start ojod

printDelimiter
echo -e "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
echo -e "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printDelimiter