#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/staketown/utils/master/common.sh)

printLogo

options=("umee-1" "canon-4")
PS3='Select your chain: '
selected="You choose the chain: "
CHAIN_ID=
CURRENCY_URL=
ENDPOINTS_URL=
DEVIATION_URL=
VERSION=
GAS_PREVOTE=
GAS_VOTE=

select opt in "${options[@]}"
do
    case $opt in
        "${options[0]}")
            # umee-1
            echo "$selected $opt"
            VERSION=umee/v2.4.3
            GAS_PREVOTE=55000
            GAS_VOTE=160000
            CHAIN_ID=$opt
            CURRENCY_URL=https://raw.githubusercontent.com/ojo-network/price-feeder/umee/umee-provider-config/currency-pairs.toml
            ENDPOINTS_URL=https://raw.githubusercontent.com/ojo-network/price-feeder/umee/umee-provider-config/endpoints.toml
            DEVIATION_URL=https://raw.githubusercontent.com/ojo-network/price-feeder/umee/umee-provider-config/deviation-thresholds.toml
            break
            ;;
        "${options[1]}")
            # canon-4
            echo "$selected $opt"
            VERSION=umee/v2.4.4-rc1
            GAS_PREVOTE=55000
            GAS_VOTE=160000
            CHAIN_ID=$opt
            CURRENCY_URL=https://raw.githubusercontent.com/ojo-network/price-feeder/sai/adding_bld_pf_cfg/umee-provider-config/currency-pairs.toml
            ENDPOINTS_URL=https://raw.githubusercontent.com/ojo-network/price-feeder/sai/adding_bld_pf_cfg/umee-provider-config/endpoints.toml
            DEVIATION_URL=https://raw.githubusercontent.com/ojo-network/price-feeder/sai/adding_bld_pf_cfg/umee-provider-config/deviation-thresholds.toml
            break
            ;;
        *) echo "unknown option $REPLY"
          exit 1
          ;;
    esac
done

read -r -p "Enter your main wallet address (that is used by validator): " MAIN_WALLET
read -r -p "Enter password to you main wallet: " WALLET_PASS

printGreen "Creating wallet for price feeder"
echo $WALLET_PASS | umeed keys add price_feeder_wallet --keyring-backend os
printDelimiter
printGreen "Your price feeder wallet name: price_feeder_wallet"
printDelimiter

printDelimiter
printGreen "Install price feeder"
cd $HOME || return
rm umee-price-feeder -rf
git clone https://github.com/ojo-network/price-feeder umee-price-feeder
cd umee-price-feeder || return
git checkout $VERSION
make build
sudo mv ./build/price-feeder /usr/local/bin/umee-price-feeder
rm $HOME/.umee-price-feeder -rf
mkdir $HOME/.umee-price-feeder

curl -s $CURRENCY_URL > $HOME/.umee-price-feeder/currency-pairs.toml
curl -s $DEVIATION_URL > $HOME/.umee-price-feeder/deviation-thresholds.toml
curl -s $ENDPOINTS_URL > $HOME/.umee-price-feeder/endpoints.toml
curl -s https://raw.githubusercontent.com/ojo-network/price-feeder/umee/price-feeder.example.toml > $HOME/.umee-price-feeder/config.toml

printDelimiter
printGreen "Configure price feeder"

KEYRING="os"
LISTEN_PORT=7173
RPC_PORT=$(grep -A 3 "\[rpc\]" ~/.umee/config/config.toml | egrep -o ":[0-9]+" | awk '{print substr($0, 2)}')
GRPC_PORT=$(grep -A 6 "\[grpc\]" ~/.umee/config/app.toml | egrep -o ":[0-9]+" | awk '{print substr($0, 2)}')
VALIDATOR_ADDRESS=$(echo $WALLET_PASS | umeed keys show $MAIN_WALLET --bech val -a)
MAIN_WALLET_ADDRESS=$(echo $WALLET_PASS | umeed keys show $MAIN_WALLET -a)
PRICEFEEDER_ADDRESS=$(echo $WALLET_PASS | umeed keys show price_feeder_wallet --keyring-backend os -a)

sed -i "s/^listen_addr *=.*/listen_addr = \"0.0.0.0:${LISTEN_PORT}\"/;\
s/^gas_prevote *=.*/gas_prevote = \"$GAS_PREVOTE\"/;\
s/^gas_vote *=.*/gas_vote = \"$GAS_VOTE\"/;\
s/^config_dir *=.*/config_dir = \"$HOME/.umee-price-feeder\"/;\
s/^address *=.*/address = \"$PRICEFEEDER_ADDRESS\"/;\
s/^chain_id *=.*/chain_id = \"$CHAIN_ID\"/;\
s/^validator *=.*/validator = \"$VALIDATOR_ADDRESS\"/;\
s/^backend *=.*/backend = \"$KEYRING\"/;\
s|^dir *=.*|dir = \"$HOME/.umee\"|;\
s|^grpc_endpoint *=.*|grpc_endpoint = \"localhost:${GRPC_PORT}\"|;\
s|^tmrpc_endpoint *=.*|tmrpc_endpoint = \"http://localhost:${RPC_PORT}\"|;\
s|^global-labels *=.*|global-labels = [[\"chain_id\", \"$CHAIN_ID\"]]|;\
s|^service-name *=.*|service-name = \"umee-price-feeder\"|;" $HOME/.umee-price-feeder/config.toml

printGreen "Sending 1 umee from $MAIN_WALLET to price feeder wallet: price_feeder_wallet"
echo $WALLET_PASS | umeed tx bank send $MAIN_WALLET_ADDRESS $PRICEFEEDER_ADDRESS 1000000uumee --from $MAIN_WALLET_ADDRESS --chain-id $CHAIN_ID --fees 20000uumee --gas-adjustment 1.4 --gas auto -y

printGreen "Waiting 5 seconds..." && sleep 5
printGreen "Delegate price feeder responsibility"
echo $WALLET_PASS | umeed tx oracle delegate-feed-consent $MAIN_WALLET_ADDRESS $PRICEFEEDER_ADDRESS --from $MAIN_WALLET_ADDRESS --chain-id $CHAIN_ID --gas-adjustment 1.4 --fees 20000uumee --gas auto -y


printGreen "Install systemd service for price feeder"

sudo tee /etc/systemd/system/umee-price-feeder.service > /dev/null <<EOF
[Unit]
Description=Umee Price Feeder
After=network-online.target

[Service]
User=$USER
ExecStart=$(which umee-price-feeder) $HOME/.umee-price-feeder/config.toml --skip-provider-check
Restart=on-failure
RestartSec=30
LimitNOFILE=65535
Environment="PRICE_FEEDER_PASS=$WALLET_PASS"

[Install]
WantedBy=multi-user.target
EOF


printGreen "Register and start the systemd service"
sudo systemctl daemon-reload
sudo systemctl enable umee-price-feeder
sudo systemctl restart umee-price-feeder


if [[ `service umee-price-feeder status | grep active` =~ "running" ]]; then
  printGreen "Price feeder has been created successfully"
  printGreen "Check logs: journalctl -u umee-price-feeder -f -o cat"
else
  printGreen "Price feeder hasn't been created correctly."
fi