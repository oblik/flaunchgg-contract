#!/bin/bash

mkdir -p addresses

find broadcast/Deploy.s.sol -name "run-latest.json" | while read -r input_file; do
    if [ -z "$input_file" ]; then
        echo "No run-latest.json files found."
        continue
    fi
    
    network_id=$(echo "$input_file" | grep -o '/[0-9]*/run' | grep -o '[0-9]*')
    output_file="addresses/${network_id}.json"

    start_block_hex=$(jq -r '.receipts[0].blockNumber // empty' "$input_file")
    
    if [ -z "$start_block_hex" ]; then
        echo "No valid blockNumber found in $input_file. Skipping."
        continue
    fi
    
    start_block=$((16#${start_block_hex#0x}))

    jq --argjson startBlock "$start_block" \
       --argjson chainId "$network_id" \
       '
       {
           chainInfo: {
               chainId: $chainId,
               startBlock: $startBlock
           },
           addresses: (
               .transactions
               | map(select(.transactionType == "CREATE" and (.arguments[0] != "Foo")))
               | map(
                   if .contractName == "Token" then
                       { ((.arguments[0] // "unknown")): .contractAddress }
                   else
                       { ((.contractName // "unknown")): .contractAddress }
                   end
               )
               | add
           )
       }
       ' "$input_file" > temp_output.json

    jq '.addresses | keys[]' temp_output.json | while read -r key; do
        key=$(echo "$key" | tr -d '"')
        address=$(jq -r --arg key "$key" '.addresses[$key]' temp_output.json)
        checksum_address=$(cast to-check-sum-address "$address")
        jq --arg key "$key" --arg value "$checksum_address" '.addresses[$key] = $value' temp_output.json > temp_output.json.tmp && mv temp_output.json.tmp temp_output.json
    done

    mv temp_output.json "$output_file"

    if [ $? -ne 0 ]; then
        echo "Error processing $input_file"
        continue
    fi
done
