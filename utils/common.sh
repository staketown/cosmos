#!/bin/bash

function printDelimiter {
  echo "==========================================="
}

function printLogo {
  bash <(curl -s "https://raw.githubusercontent.com/R1M-NODES/cosmos/master/utils/logo.sh")
}

printLogo