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
 
 b_username=$(yq '.bitcoind.user' /data/start9/config.yaml)
 b_password=$(yq '.bitcoind.password' /data/start9/config.yaml)
 
 # Get blockchain info from the bitcoin rpc
 b_gbc_result=$(curl -sS --user $b_username:$b_password --data-binary '{"jsonrpc": "1.0", "id": "sync-hck", "method": "getblockchaininfo", "params": []}' -H 'content-type: text/plain;' http://$b_host:$b_port/ 2>&1)
 error_code=$?
 b_gbc_error=$(echo $b_gbc_result | yq '.error' -)
 if [[ $error_code -ne 0 ]]; then
    echo "Error contacting Bitcoin RPC: $b_gbc_result" >&2
    exit 61
 elif [ "$b_gbc_error" != "null" ] ; then
    echo "Bitcoin RPC returned error: $b_gbc_error" >&2
    exit 61
 fi

 b_block_count=$(echo "$b_gbc_result" | yq '.result.blocks' -)
 b_block_ibd=$(echo "$b_gbc_result" | yq '.result.initialblockdownload' -)
 if [ "$b_block_count" = "null" ]; then
    echo "Error ascertaining Bitcoin blockchain status: $b_gbc_error" >&2
    exit 61
 elif [ "$b_block_ibd" != "false" ] ; then
    b_block_hcount=$(echo "$b_gbc_result" | yq '.result.headers' -)
    echo -n "Bitcoin blockchain is not fully synced yet: $b_block_count of $b_block_hcount blocks" >&2
    echo " ($(expr ${b_block_count}00 / $b_block_hcount)%)" >&2
    exit 61
 else
    # Check Fulcrum sync status via server.banner
    banner_res=$(echo '{"jsonrpc": "2.0", "method": "server.banner", "params": [], "id": 1}' | curl -s --data-binary @- http://127.0.0.1:50001)
    error_code=$?
    
    if [[ $error_code -ne 0 ]]; then
        echo "Error contacting Fulcrum RPC" >&2
        exit 61
    fi

    # Check if Fulcrum is still syncing by looking for "Syncing" in the banner
    if echo "$banner_res" | grep -q "Syncing"; then
        echo "Fulcrum is still syncing..." >&2
        exit 61
    else
        # Verify we can get server features
        features_res=$(echo '{"jsonrpc": "2.0", "method": "server.features", "params": [], "id": 0}' | curl -s --data-binary @- http://127.0.0.1:50001)
        if [ -n "$features_res" ] && ! echo "$features_res" | grep -q "error"; then
            # Fulcrum is synced and responding
            exit 0
        else
            echo "Fulcrum RPC is not responding correctly" >&2
            exit 61
        fi
    fi
 fi
fi

