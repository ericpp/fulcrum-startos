#!/bin/sh

set -e

# Get config
BITCOIND_TYPE=$(yq e '.bitcoind.type' /data/start9/config.yaml)

# Set RPC port based on bitcoind type
if [ "$BITCOIND_TYPE" = "internal-testnet" ]; then
    export BITCOIND_RPC_PORT=48332
    export BITCOIND_HOST="bitcoind-testnet.embassy"
else
    export BITCOIND_RPC_PORT=8332
    export BITCOIND_HOST="bitcoind.embassy"
fi

if [ ! -e "$SSL_CERTFILE" ] || [ ! -e "$SSL_KEYFILE" ] ; then
  openssl req -newkey rsa:2048 -sha256 -nodes -x509 -days 365 -subj "/O=Fulcrum" -keyout "$SSL_KEYFILE" -out "$SSL_CERTFILE"
fi

if [ "$1" = "Fulcrum" ] ; then
  set -- "$@" -D "$DATA_DIR" -c "$SSL_CERTFILE" -k "$SSL_KEYFILE"
fi

# todo
# echo 'db/' > /data/.backupignore
# echo 'core' >> /data/.backupignore

TOR_ADDRESS=$(yq '.electrum-tor-address' /data/start9/config.yaml)

cat << EOF > /data/start9/stats.yaml
---
version: 2
data:
  Quick Connect URL:
    type: string
    value: $TOR_ADDRESS:50001:t
    description: For scanning into wallets such as BlueWallet
    copyable: true
    qr: true
    masked: true
  Hostname:
    type: string
    value: $TOR_ADDRESS
    description: Hostname to input into wallet software such as Sparrow.
    copyable: true
    qr: false
    masked: true
  Port:
    type: string
    value: "50001"
    description: Port to input into wallet software such as Sparrow.
    copyable: true
    qr: false
    masked: false
EOF

configurator
exec tini -p SIGTERM -- Fulcrum /data/fulcrum.conf
