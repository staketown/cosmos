#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/R1M-NODES/utils/master/common.sh)

printLogo

read -r -p "Enter your main wallet: " MAIN_WALLET
read -r -p "Enter password to you wallet: " WALLET_PASS

printGreen "Creating wallet for price feeder"
echo $WALLET_PASS | ojod keys add price_feeder_wallet --keyring-backend os
printDelimiter
printGreen "Your price feeder wallet name: price_feeder_wallet"
printDelimiter

printDelimeter
printGreen "Install price feeder"
cd $HOME && rm price-feeder -rf
git clone https://github.com/ojo-network/price-feeder
cd price-feeder || return
git checkout v0.1.1
make build
sudo mv ./build/price-feeder /usr/local/bin
rm $HOME/.ojo-price-feeder -rf
mkdir $HOME/.ojo-price-feeder
mv price-feeder.example.toml $HOME/.ojo-price-feeder/config.toml

printDelimiter
printGreen "Configure price feeder"
KEYRING="os"
LISTEN_PORT=7172
RPC_PORT=$(grep -A 3 "\[rpc\]" ~/.ojo/config/config.toml | egrep -o ":[0-9]+" | awk '{print substr($0, 2)}')
GRPC_PORT=$(grep -A 6 "\[grpc\]" ~/.ojo/config/app.toml | egrep -o ":[0-9]+" | awk '{print substr($0, 2)}')
VALIDATOR_ADDRESS=$(echo $WALLET_PASS | ojod keys show $MAIN_WALLET --bech val -a)
MAIN_WALLET_ADDRESS=$(echo $WALLET_PASS | ojod keys show $MAIN_WALLET -a)
PRICEFEEDER_ADDRESS=$(echo $WALLET_PASS | ojod keys show price_feeder_wallet --keyring-backend os -a)

sed -i "s/^listen_addr *=.*/listen_addr = \"0.0.0.0:${LISTEN_PORT}\"/;\
s/^address *=.*/address = \"$PRICEFEEDER_ADDRESS\"/;\
s/^chain_id *=.*/chain_id = \"ojo-devnet\"/;\
s/^validator *=.*/validator = \"$VALIDATOR_ADDRESS\"/;\
s/^backend *=.*/backend = \"$KEYRING\"/;\
s|^dir *=.*|dir = \"$HOME/.ojo\"|;\
s|^grpc_endpoint *=.*|grpc_endpoint = \"localhost:${GRPC_PORT}\"|;\
s|^tmrpc_endpoint *=.*|tmrpc_endpoint = \"http://localhost:${RPC_PORT}\"|;\
s|^global-labels *=.*|global-labels = [[\"chain_id\", \"ojo-devnet\"]]|;\
s|^service-name *=.*|service-name = \"ojo-price-feeder\"|;" $HOME/.ojo-price-feeder/config.toml

printGreen "Sending 1 OJO from $MAIN_WALLET to price feeder wallet: price_feeder_wallet"
echo $WALLET_PASS | ojod tx bank send wallet $PRICEFEEDER_ADDRESS 1000000uojo --from $MAIN_WALLET_ADDRESS --chain-id ojo-devnet --gas-adjustment 1.4 --gas auto --gas-prices 0uojo -y

printGreen "Waiting 5 seconds..." && sleep 5
printGreen "Delegate price feeder responsibility"
echo $WALLET_PASS | ojod tx oracle delegate-feed-consent $MAIN_WALLET_ADDRESS $PRICEFEEDER_ADDRESS --from wallet --gas-adjustment 1.4 --gas auto --gas-prices 0uojo -y


printGreen "Install systemd service for price feeder"

sudo tee /etc/systemd/system/ojo-price-feeder.service > /dev/null <<EOF
[Unit]
Description=Ojo Price Feeder
After=network-online.target

[Service]
User=$USER
ExecStart=$(which price-feeder) $HOME/.ojo-price-feeder/config.toml
Restart=on-failure
RestartSec=30
LimitNOFILE=65535
Environment="PRICE_FEEDER_PASS=$WALLET_PASS"

[Install]
WantedBy=multi-user.target
EOF


printGreen "Register and start the systemd service"
sudo systemctl daemon-reload
sudo systemctl enable ojo-price-feeder
sudo systemctl restart ojo-price-feeder


if [[ `service ojo-price-feeder status | grep active` =~ "running" ]]; then
  printGreen "Price feeder has been created successfully"
  printGreen "Check logs: journalctl -u ojo-price-feeder -f -o cat"
else
  printGreen "Price feeder hasn't been created correctly."
fi