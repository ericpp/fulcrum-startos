#!/bin/bash

DURATION=$(</dev/stdin)
if (($DURATION <= 9000 )); then
    exit 60
else
 set -e
 
 # Read config to determine if we're using testnet
 config_type=$(yq '.bitcoind.type' /data/start9/config.yaml)
 
 if [ "$config_type" = "bitcoind-testnet" ]; then
    b_host="bitcoind-testnet.embassy"
    b_port="48332"  # Changed from 18332 to 48332
 else
    b_host="bitcoind.embassy"
    b_port="8332"
 fi
 
 b_username=$(yq '.bitcoind.username' /data/start9/config.yaml)
 b_password=$(yq '.bitcoind.password' /data/start9/config.yaml)

    # Debug: Print values (except password)
    echo "Debug: Type = $config_type" >&2
    echo "Debug: Host = $b_host" >&2
    echo "Debug: Port = $b_port" >&2
    echo "Debug: Username = $b_username" >&2

    # Get blockchain info
    b_gbc_result=$(curl -s --user "$b_username:$b_password" \
        --data-binary '{"jsonrpc": "1.0", "id": "sync-hck", "method": "getblockchaininfo", "params": []}' \
        -H 'content-type: text/plain;' \
        "http://$b_host:$b_port/" 2>&1)
    
    # If Fulcrum is running and responding, consider it healthy
    if curl -s telnet://127.0.0.1:50001 > /dev/null; then
        echo "Fulcrum is running and responding" >&2
        exit 0
    else
        echo "Fulcrum is not responding" >&2
        exit 1
    fi
fi

