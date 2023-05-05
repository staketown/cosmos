#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="testnet3"
CHAIN_DENOM="aCC"
BINARY_NAME="cascadiad"
BINARY_VERSION_TAG="v0.1.1"
CHEAT_SHEET="https://nodes.stake-town.com/casandra"

printDelimiter
echo -e "Node moniker:       $NODE_MONIKER"
echo -e "Chain id:           $CHAIN_ID"
echo -e "Chain demon:        $CHAIN_DENOM"
echo -e "Binary version tag: $BINARY_VERSION_TAG"
printDelimiter && sleep 1

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/dependencies.sh)

echo "" && printGreen "Building binaries..." && sleep 1

cd || return
curl -L https://github.com/DecentralCardGame/Cardchain/releases/download/v0.81/Cardchain_latest_linux_amd64.tar.gz > Cardchain_latest_linux_amd64.tar.gz
tar -xvzf Cardchain_latest_linux_amd64.tar.gz
chmod +x Cardchaind && mkdir -p $HOME/go/bin
mv Cardchaind $HOME/go/bin
rm Cardchain_latest_linux_amd64.tar.gz

Cardchaind config keyring-backend test
Cardchaind config chain-id $CHAIN_ID
Cardchaind init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -s https://raw.githubusercontent.com/DecentralCardGame/Testnet/main/genesis.json > $HOME/.Cardchain/config/genesis.json

CONFIG_TOML=$HOME/.Cardchain/config/config.toml
PEERS="b651ea2a0517e82c1a476e25966ab3de3159afe8@34.229.22.39:26656,3b389873f999763d3f937f63f765f0948411e296@44.192.85.92:26656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS=""
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.Cardchain/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.0025aCC"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.Cardchain/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/Cardchaind.service > /dev/null << EOF
[Unit]
Description=Cardchain Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which Cardchaind) start
Restart=on-failure
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF

Cardchaind unsafe-reset-all

# Add snapshot here
curl -s https://snapshots1-testnet.nodejumper.io/cardchain-testnet/addrbook.json > $HOME/.Cardchain/config/addrbook.json
SNAP_NAME=$(curl -s https://snapshots1-testnet.nodejumper.io/cardchain-testnet/info.json | jq -r .fileName)
curl "https://snapshots1-testnet.nodejumper.io/cardchain-testnet/${SNAP_NAME}" | lz4 -dc - | tar -xf - -C "$HOME/.Cardchain"

#URL="https://snapshots-testnet.stake-town.com/cascadia/cascadia_6102-1_latest.tar.lz4"
#curl $URL | lz4 -dc - | tar -xf - -C $HOME/.Cardchain

sudo systemctl daemon-reload
sudo systemctl enable Cardchaind
sudo systemctl start Cardchaind

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter