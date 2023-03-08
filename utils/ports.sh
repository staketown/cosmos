#!/bin/bash

# default ports for cosmos
PORT_GRPC=9090
PORT_GRPC_WEB=9091
PORT_PROXY_APP=26658
PORT_RPC=26657
PORT_PPROF_LADDR=26656
PORT_P2P=6060
PORT_PROMETHEUS=26660
PORT_API=1317

source <(curl -s https://raw.githubusercontent.com/R1M-NODES/cosmos/master/utils/common.sh)

function persistPorts {
    ARG=$(($1 - 1))

    echo "export PORT_GRPC=`expr $PORT_GRPC \+ 100 \* $ARG`" >> $HOME/.bash_profile
    echo "export PORT_GRPC_WEB=`expr $PORT_GRPC_WEB \+ 100 \* $ARG`"  >> $HOME/.bash_profile
    echo "export PORT_PROXY_APP=`expr $PORT_PROXY_APP \+ 1000 \* $ARG`"  >> $HOME/.bash_profile
    echo "export PORT_RPC=`expr $PORT_RPC \+ 1000 \* $ARG`"  >> $HOME/.bash_profile
    echo "export PORT_PPROF_LADDR=`expr $PORT_PPROF_LADDR \+ 1000 \* $ARG`"  >> $HOME/.bash_profile
    echo "export PORT_P2P=`expr $PORT_P2P \+ 100 \* $ARG`"  >> $HOME/.bash_profile
    echo "export PORT_PROMETHEUS=`expr $PORT_PROMETHEUS \+ 1000 \* $ARG`"  >> $HOME/.bash_profile
    echo "export PORT_API=`expr $PORT_API \+ 100 \* $ARG`"  >> $HOME/.bash_profile
}

function exportPorts {
    ARG=$(($1 - 1))

    export PORT_GRPC=`expr $PORT_GRPC \+ 100 \* $ARG`
    export PORT_GRPC_WEB=`expr $PORT_GRPC_WEB \+ 100 \* $ARG`
    export PORT_PROXY_APP=`expr $PORT_PROXY_APP \+ 1000 \* $ARG`
    export PORT_RPC=`expr $PORT_RPC \+ 1000 \* $ARG`
    export PORT_PPROF_LADDR=`expr $PORT_PPROF_LADDR \+ 1000 \* $ARG`
    export PORT_P2P=`expr $PORT_P2P \+ 100 \* $ARG`
    export PORT_PROMETHEUS=`expr $PORT_PROMETHEUS \+ 1000 \* $ARG`
    export PORT_API=`expr $PORT_API \+ 100 \* $ARG`

    echo "The following ports will be used: $PORT_GRPC $PORT_GRPC_WEB $PORT_PROXY_APP $PORT_RPC $PORT_PPROF_LADDR $PORT_P2P $PORT_PROMETHEUS $PORT_API"
}

echo ""
echo "Here available port sets to use:"
printDelimiter
echo    "1 (default) - 9090, 9091, 26658, 26657, 26656, 6060, 26660, 1317"
echo    "2           - 9190, 9191, 27658, 27657, 27656, 6160, 27660, 1417"
echo    "3           - 9290, 9291, 28658, 28657, 28656, 6260, 28660, 1517"
echo    "4           - 9390, 9391, 29658, 29657, 29656, 6360, 29660, 1617"
echo    "5           - 9490, 9491, 30658, 30657, 30656, 6460, 30660, 1717"
echo    "6           - 9590, 9591, 31658, 31657, 31656, 6560, 31660, 1817"
echo    "7           - 9690, 9691, 32658, 32657, 32656, 6660, 32660, 1917"
echo    "8           - 9790, 9791, 33658, 33657, 33656, 6760, 33660, 2017"
echo    "9           - 9890, 9891, 34658, 34657, 34656, 6860, 34660, 2117"
printDelimiter
echo ""

read -r -p "${1:-Choose ports you would like to use: } " flag
case "${flag}" in
  1) persistPorts 1 ;;
  2) persistPorts 2 ;;
  3) persistPorts 3 ;;
  4) persistPorts 4 ;;
  5) persistPorts 5 ;;
  6) persistPorts 6 ;;
  7) persistPorts 7 ;;
  8) persistPorts 8 ;;
  9) persistPorts 9 ;;
  *) echo "WARN: unknown parameter: ${flag}" && exit 1
esac

source $HOME/.bash_profile