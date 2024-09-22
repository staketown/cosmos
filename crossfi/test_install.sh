#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

source <(curl -s https://raw.githubusercontent.com/staketown/cosmos/master/utils/ports.sh) && sleep 1
export -f selectPortSet && selectPortSet

read -r -p "Enter node moniker: " NODE_MONIKER

CHAIN_ID="crossfi-evm-testnet-1"
CHAIN_DENOM="mpx"
BINARY_NAME="crossfid"
BINARY_VERSION_TAG="0.3.0-prebuild9"
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
curl -L https://github.com/crossfichain/crossfi-node/releases/download/v0.3.0-prebuild9/crossfi-node_0.3.0-prebuild9_linux_amd64.tar.gz > crossfi-node_0.3.0-prebuild9_linux_amd64.tar.gz
tar -xvzf crossfi-node_0.3.0-prebuild9_linux_amd64.tar.gz
chmod +x $HOME/bin/crossfid
mv $HOME/bin/crossfid $HOME/go/bin
rm -rf crossfi-node_0.3.0-prebuild9_linux_amd64.tar.gz readme.md $HOME/bin

crossfid config keyring-backend os
crossfid config chain-id $CHAIN_ID
crossfid init "$NODE_MONIKER" --chain-id $CHAIN_ID

curl -s https://snapshots-testnet.stake-town.com/crossfi/genesis.json > $HOME/.crossfid/config/genesis.json
curl -s https://snapshots-testnet.stake-town.com/crossfi/addrbook.json > $HOME/.crossfid/config/addrbook.json

CONFIG_TOML=$HOME/.crossfid/config/config.toml
PEERS=""
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $CONFIG_TOML
SEEDS="89752fa7945a06e972d7d860222a5eeaeab5c357@128.140.70.97:26656,dd83e3c7c4e783f8a46dbb010ec8853135d29df0@crossfi-testnet-seed.itrocket.net:36656"
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" $CONFIG_TOML

APP_TOML=$HOME/.crossfid/config/app.toml
sed -i 's|^pruning *=.*|pruning = "custom"|g' $APP_TOML
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $APP_TOML
sed -i 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|g' $APP_TOML
sed -i 's|^pruning-interval *=.*|pruning-interval = "19"|g' $APP_TOML
sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $CONFIG_TOML
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $CONFIG_TOML
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "5000000000mpx"|g' $APP_TOML

# Customize ports
CLIENT_TOML=$HOME/.crossfid/config/client.toml
sed -i.bak -e "s/^external_address *=.*/external_address = \"$(wget -qO- eth0.me):$PORT_PPROF_LADDR\"/" $CONFIG_TOML
sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:$PORT_PROXY_APP\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:$PORT_RPC\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:$PORT_P2P\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:$PORT_PPROF_LADDR\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":$PORT_PROMETHEUS\"%" $CONFIG_TOML && \
sed -i.bak -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:$PORT_GRPC\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:$PORT_GRPC_WEB\"%; s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:$PORT_API\"%; s%^address = \"127.0.0.1:8545\"%address = \"0.0.0.0:$PORT_EVM_RPC\"%; s%^ws-address = \"127.0.0.1:8546\"%ws-address = \"0.0.0.0:$PORT_EVM_WS\"%; s%^metrics-address = \"127.0.0.1:6065\"%metrics-address = \"0.0.0.0:$PORT_EVM_METRICS\"%" $APP_TOML && \
sed -i.bak -e "s%^node = \"tcp://localhost:26657\"%node = \"tcp://localhost:$PORT_RPC\"%" $CLIENT_TOML

printGreen "Install and configure cosmovisor..." && sleep 1

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.4.0
mkdir -p ~/.crossfid/cosmovisor/genesis/bin
mkdir -p ~/.crossfid/cosmovisor/upgrades
cp ~/go/bin/crossfid $HOME/.crossfid/cosmovisor/genesis/bin

printGreen "Starting service and synchronization..." && sleep 1

sudo tee /etc/systemd/system/crossfid.service > /dev/null << EOF
[Unit]
Description=CrossFi Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="DAEMON_NAME=crossfid"
Environment="DAEMON_HOME=$HOME/.crossfid"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
[Install]
WantedBy=multi-user.target
EOF

crossfid tendermint unsafe-reset-all --home $HOME/.crossfid --keep-addr-book

# Add snapshot here
URL="https://snapshots-testnet.stake-town.com/crossfi/crossfi-evm-testnet-1_latest.tar.lz4"
curl $URL | lz4 -dc - | tar -xf - -C $HOME/.crossfid
[[ -f $HOME/.crossfid/data/upgrade-info.json ]] && cp $HOME/.crossfid/data/upgrade-info.json $HOME/.crossfid/cosmovisor/genesis/upgrade-info.json

sudo systemctl daemon-reload
sudo systemctl enable crossfid
sudo systemctl start crossfid

printDelimiter
printGreen "Check logs:            sudo journalctl -u $BINARY_NAME -f -o cat"
printGreen "Check synchronization: $BINARY_NAME status 2>&1 | jq .SyncInfo.catching_up"
printGreen "Check our cheat sheet: $CHEAT_SHEET"
printDelimiter