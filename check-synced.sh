#!/bin/bash

DURATION=$(</dev/stdin)
if (($DURATION <= 9000 )); then
    exit 60
else
 set -e

 b_type=$(yq '.bitcoind.type' /data/start9/config.yaml)
 b_host="${b_type}.embassy"

 if [ "$b_host" = "bitcoind-testnet.embassy" ]; then
    b_port=48332
 else
    b_port=8332
 fi

 b_username=$(yq '.bitcoind.username' /data/start9/config.yaml)
 b_password=$(yq '.bitcoind.password' /data/start9/config.yaml)

 #Get blockchain info from the bitcoin rpc
 b_gbc_result=$(curl -sS --user $b_username:$b_password --data-binary '{"jsonrpc": "1.0", "id": "sync-hck", "method": "getblockchaininfo", "params": []}' -H 'content-type: text/plain;' http://$b_host:$b_port/ 2>&1)
 error_code=$?
 b_gbc_error=$(echo $b_gbc_result | yq '.error' -)
 if [[ $error_code -ne 0 ]]; then
    echo "Error contacting Bitcoin RPC: $b_gbc_result" >&2
    exit 61
 elif [ "$b_gbc_error" != "null" ] ; then
    #curl returned ok, but the "good" result could be an error like:
    # '{"result":null,"error":{"code":-28,"message":"Verifying blocks…"},"id":"sync-hck"}'
    # meaning bitcoin is not yet synced.  Display that "message" and exit:
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
    #Gather keys/values from stats endpoint
    curl_res=$(curl -sS http://localhost:8080/stats)
    error_code=$?

    if [[ $error_code -ne 0 ]]; then
        echo "Error contacting the Fulcrum stats server" >&2
        exit 61
    fi

    synced_height=$(echo -e "$curl_res" | yq '.Controller.["Header count"]')
    if [ -n "$synced_height" ] && [[ $synced_height -ge 0 ]] ; then
        if [[ $synced_height -lt $b_block_count ]] ; then
            echo "Catching up to blocks from bitcoind. This should take at most a day. Progress: $synced_height of $b_block_count blocks ($(expr ${synced_height}00 / $b_block_count)%)" >&2
            exit 61
        else
            #Check to make sure the Fulcrum RPC is actually up and responding
            features_res=$(echo '{"jsonrpc": "2.0", "method": "server.features", "params": [], "id": 0}' | netcat -w 1 127.0.0.1 50001)
            server_string=$(echo $features_res | yq '.result.server_version')
            if [ -n "$server_string" ] ; then
                #Index is synced to tip
                exit 0
            else
                echo "Fulcrum RPC is not responding." >&2
                exit 61
            fi
        fi
    elif [ -z "$synced_height" ] ; then
        echo "Fulcrum is not yet returning the sync status" >&2
        exit 61
    fi
 fi
fi