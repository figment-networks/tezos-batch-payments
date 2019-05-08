#!/usr/bin/env bash

###
### Usage help and command line argument handling
###

function usage() {
  echo "Usage instructions:"
  echo "bash tezos-batch-payments.bash [options]"
  echo -e "  -h --help\t\tPrint this help info."
  echo -e "  --fee AMOUNT\tOverride per-transaction fee (default: 1110 µXTZ)."
  echo -e "  --transactions\tTransactions to run. E.g. \`ADDR1=AMOUNT1,ADDR2=AMOUNT2,...\`"
  echo -e "  --transactions-file\tPath to a file with one \`ADDR=AMOUNT\` per line."
  echo -e "  --docker NETWORK\tUse this option if you use are using the docker scripts to run your node."
  echo -e "  --use NAME\t\tSpecify the name (alias) of an account to use."
  echo -e "  --skip-funding\tDon't ask to fund the account (for instance if it's already funded)."
  echo -e "  --check\t\tCheck node access, parse provided transactions and show the total, then exit."
  echo -e "  --debug\t\tWill output a bunch of extra info during processing."
  echo
  echo "* Note: All 'AMOUNT' values must be in µXTZ (multiply XTZ by 1,000,000)"
  echo "        e.g. to send 12.052 XTZ, specify 12052000 as AMOUNT"
  echo
}

while [[ $# -gt 0 ]]; do
  param="$1"
  case $param in
    -h | --help)
      usage
      exit
      ;;
    --debug)
      DEBUG=Y
      shift
      ;;
    --check)
      CHECK_ONLY=Y
      shift
      ;;
    --skip-funding)
      SKIP_FUNDING=Y
      shift
      ;;
    --use)
      ACCOUNT_NAME=$2
      shift
      shift
      ;;
    --docker)
      DOCKER=Y
      CLIENT_CMD="docker exec -e TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y -t $2_node_1 tezos-client"
      shift
      shift
      ;;
    --transactions-file|--transactions)
      TRANSACTIONS="[]"
      if [[ "$param" == "--transactions" ]]; then
        IFS=',' read -ra PAIRS <<< "$2"
      else
        IFS=$'\n' read -d '' -r -a PAIRS < "$2"
      fi

      for pair in "${PAIRS[@]}"; do
        addr=`echo $pair | awk -F= '{print $1}'`
        amount=`echo $pair | awk -F= '{print $2}'`

        TRANSACTIONS=$(echo "$TRANSACTIONS" | jq \
          --compact-output \
          --arg address $addr \
          --arg amount $amount \
          '. |= . + [{
            "kind": "transaction",
            "amount": $amount,
            "destination": $address,
            "storage_limit": "0",
            "gas_limit": "10300",
            "fee": "1110"
          }]'
        )
      done
      shift
      shift
      ;;
    --fee)
      FEE_OVERRIDE=$2
      shift
      shift
      ;;
    *)
      echo "ERROR: unknown parameter \"$param\""
      usage
      exit 1
      ;;
  esac
done

checkDepsAndArgs() {
  ###
  ### tezos-client or docker must be in path
  ###

  if [[ $DOCKER == 'Y' ]]; then
    bash -c "which docker > /dev/null 2>&1"
    if [ ! $? -eq 0 ]; then
      echo "This script requires 'docker' to be installed."
      exit 1
    fi
  else
    bash -c "which tezos-client > /dev/null 2>&1"
    if [ ! $? -eq 0 ]; then
      CLIENT_CMD="./tezos-client"
    else
      CLIENT_CMD="tezos-client"
    fi

    bash -c "$CLIENT_CMD man > /dev/null 2>&1"
    if [ ! $? -eq 0 ]; then
      echo "This script requires 'tezos-client' to be in the current directory, or \$PATH"
      exit 1
    fi
  fi


  ###
  ### jq is required to run this script
  ###

  bash -c "which jq > /dev/null 2>&1"
  if [ ! $? -eq 0 ]; then
    echo "This script requires 'jq' to be installed."
    exit 1
  fi


  ###
  ### dc is required to run this script
  ###

  bash -c "which dc > /dev/null 2>&1"
  if [ ! $? -eq 0 ]; then
    echo "This script requires 'dc' to be installed."
    exit 1
  fi


  ###
  ### Just a big ol' header
  ###

  echo "****************************************************************"
  echo "***             Tezos Batch Payout Script                    ***"
  echo "***                by Figment Networks                       ***"
  echo "***              https://figment.network                     ***"
  echo "*** https://github.com/figment-networks/tezos-batch-payments ***"
  echo "****************************************************************"
  echo


  ###
  ### Recommended to run in tmux or screen
  ###

  if [ ! -n "$STY" ] && [ ! -n "$TMUX" ]; then
    echo '*** Warning: Not running in screen or tmux session!'
    countdown=5
    while [ $countdown -gt 0 ]; do
      echo -ne "\r*** Waiting $countdown..."
      sleep 1
      countdown=$((countdown-1))
    done
    echo -e "\r*** Running anyway..."
    echo
  fi
}

function setup() {
  ###
  ### The disclaimer banner thing will cause us pain
  ###

  if [ ! -z $TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER ]; then
    RESTORE_DISCLAIMER=$TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER
  fi

  export TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y


  ###
  ### We need transactions to send ;)
  ###

  if [ -z $TRANSACTIONS ] || [[ "$TRANSACTIONS" == "[]" ]]; then
    usage
    exit 1
  fi


  ###
  ### Process transactions array by overriding fee to amount passed as arg
  ###

  if [ ! -z $FEE_OVERRIDE ]; then
    TRANSACTIONS=$(echo "$TRANSACTIONS" | jq \
      --compact-output \
      --arg fee "$FEE_OVERRIDE" \
      'map(. + { fee: $fee })'
    )
  fi


  ###
  ### Calculate the total funding needed for the entire batch
  ###

  TOTAL_REQUIRED_FUNDING=$(jq \
    --null-input \
    --compact-output \
    --argjson transactions "$TRANSACTIONS" \
    '
      $transactions |
      reduce .[] as $obj
        (0; . + (($obj.amount//0)|tonumber) +
                (($obj.fee//0)|tonumber))
    '
  )
  TOTAL_STRING=$(awk "BEGIN { printf \"%0.8g\", $TOTAL_REQUIRED_FUNDING / 1000000 }")


  ###
  ### Ready to display check info if user requested it
  ###

  if [ ! -z $CHECK_ONLY ]; then
    echo -n "Transactions valid! $(echo -n "$TRANSACTIONS" | jq '. | length') "
    echo "found for a total of $TOTAL_STRING XTZ"
    echo
    exit 0
  fi


  ###
  ### Ensure we can access the node via the command-line client
  ###

  echo -n "Checking node access... "
  bash -c "$CLIENT_CMD bootstrapped > /dev/null 2>&1"
  if [ ! $? -eq 0 ]; then
    echo "FAILED"
    exit 1
  else
    echo "OK"
  fi


  ###
  ### Ensure we have been provided an account to use
  ###

  if [ -z $ACCOUNT_NAME ]; then
    read -p "Specify float account alias: " ACCOUNT_NAME
  fi

  ACCOUNT_INFO=$(runAndClean "$CLIENT_CMD show address $ACCOUNT_NAME")
  ACCOUNT_ADDRESS=$(echo -n "$ACCOUNT_INFO" | extractRpcResponseField "Hash")
  ACCOUNT_PUBLIC_KEY=$(echo -n "$ACCOUNT_INFO" | extractRpcResponseField "Public Key")

  echo "Using account '$ACCOUNT_NAME'"
  echo


  ###
  ### Process transactions array by assigning source address
  ###

  TRANSACTIONS=$(echo "$TRANSACTIONS" | jq \
    --compact-output \
    --arg source "$ACCOUNT_ADDRESS" \
    'map(. + {
      source: $source
    })'
  )


  if [ -z $SKIP_FUNDING ]; then
    ###
    ### Request that the user fund the float account
    ###

    echo "Send $TOTAL_STRING XTZ to $ACCOUNT_ADDRESS"
    read -p "Paste operation hash: " FUNDING_OP_HASH

    if [[ $FUNDING_OP_HASH == "" ]]; then
      echo "Skipping..."
    else
      echo -n "Waiting for confirmation... "
      bash -c "$CLIENT_CMD wait for $FUNDING_OP_HASH to be included --confirmations 1 --check-previous 500 > /dev/null 2>&1"
      if [ ! $? -eq 0 ]; then
        echo "FAILED"
        exit 1
      else
        echo "OK"
      fi
    fi
  else
    echo "Skipping funding ($ACCOUNT_ADDRESS requires $TOTAL_STRING XTZ)..."
  fi
  echo
}


###
### Helper Functions
###

function log() {
  if [ ! -z $DEBUG ]; then
    echo "DEBUG -- $@"
  fi
}

function extractRpcResponseField() {
  tr '\r' '\n' | grep "$1:" | sed 's/^.*:\s//'
}

declare -a base58=(
    1 2 3 4 5 6 7 8 9
  A B C D E F G H   J K L M N   P Q R S T U V W X Y Z
  a b c d e f g h i j k   m n o p q r s t u v w x y z
)
unset dcr; for i in {0..57}; do dcr+="${i}s${base58[i]}"; done
function decodeBase58() {
  echo -n "$1" | sed -e's/^\(1*\).*/\1/' -e's/1/00/g' | tr -d '\n'
  unset hex; while read line; do hex+=$(echo -n $line | tr -d '/ \n'); done \
  <<< $(dc -e "$dcr 16o0$(sed 's/./ 58*l&+/g' <<<$1)p")
  if [ `expr $(echo -n $hex | wc -c) % 2` -gt 0 ]; then echo -n "0$hex"; else echo -n $hex; fi
}

function runAndClean() {
  bash -c "$1" | tr '\r' '\n'
}

function cleanCr() {
  echo -n $1 | tr -d '\r'
}

function rpcResponseOk() {
  if [[ $1 =~ "Fatal error:" ]] ||
     [[ $1 =~ "Error:" ]] ||
     [[ $1 =~ "Unexpected server answer" ]] ||
     [ ! $2 -eq 0 ]; then
    false
  else
    true
  fi
}

function error() {
  echo "ERROR"
  echo
  echo "$1"
  echo "INFO: ${@:2}"
  echo
  exit 1
}

function pageNumber() {
  awk "function ceiling(x){return x%1 ? int(x)+1 : x} BEGIN { print ceiling($1 / $2) }"
}

function simulateTransactions() {
  echo -n "Simulating... "
  local transactions=$1

  local head_hash=$($CLIENT_CMD rpc get /chains/main/blocks/head | jq .hash)
  if ! rpcResponseOk "$head_hash" $?; then
    error "Unable to retrieve current head." "$head_hash"
  fi

  local current_counter=$($CLIENT_CMD rpc get /chains/main/blocks/head/context/contracts/$ACCOUNT_ADDRESS/counter | tr -d '\n\r"')
  if ! rpcResponseOk "$current_counter" $?; then
    error "Unable to retrieve counter for $ACCOUNT_ADDRESS" "$current_counter"
  fi

  log "Current head: $head_hash"
  log "Current counter: $current_counter"

  transactions=$(echo "$transactions" | jq \
    --compact-output \
    --arg counter $current_counter \
    'to_entries | map(.value + {
      counter: (($counter|tonumber) + .key + 1)|tostring
    })'
  )
  log "Transactions with counter: $transactions"

  # this fake signature is the same one tezos-client uses during simulation
  # it must be a valid/decodeable signature, but the actual contents are irrelevant
  local fake_sig="edsigtXomBKi5CTRf5cjATJWSyaRvhfYNHqSUGrn4SdbYRcGwQrUGjzEfQDTuqHhuA8b2d8NarZjz8TRf65WkpQmo423BtomS8Q"
  local run_json=$(echo "{}" | jq \
    --compact-output \
    --argjson head $head_hash \
    --argjson transactions "$transactions" \
    --arg signature "$fake_sig" \
    '. + {
      branch: $head,
      contents: $transactions,
      signature: $signature
    }'
  )
  log "Simulation run JSON: $run_json"

  run_response=$($CLIENT_CMD rpc post /chains/main/blocks/head/helpers/scripts/run_operation with $run_json)

  if ! rpcResponseOk "$run_response" $?; then
    error "Transaction simulation failed. Cannot continue!" "$run_json" "$run_response"
  else
    run_response=$(cleanCr "$run_response")
    log "Results from simulation run: $run_response"
    bash -c "echo '$run_response' | jq -e '.contents | map(select(.metadata.operation_result.status == \"failed\")) | length == 0' > /dev/null 2>&1"
    if [ ! $? -eq 0 ]; then
      error "Transaction simulation failed. Cannot continue!" "$run_response"
    else
      echo "OK"
    fi
  fi
}

function sendBatch() {
  local transactions=$1

  ###
  ### Acquire various dependencies for later use
  ###  - hash of current head
  ###  - current protocol
  ###  - counter for the sender
  ###

  local current_head=$($CLIENT_CMD rpc get /chains/main/blocks/head)
  local head_hash=$(echo "$current_head" | jq .hash)
  local protocol_hash=$(echo "$current_head" | jq .metadata.protocol)

  local current_counter=$($CLIENT_CMD rpc get /chains/main/blocks/head/context/contracts/$ACCOUNT_ADDRESS/counter)
  if ! rpcResponseOk "$current_counter" $?; then
    error "Could not determine counter!" "$current_counter"
  else
    current_counter=$(echo -n "$current_counter" | tr -d '\n\r"')
    log "Current counter: $current_counter"
  fi


  ###
  ### Add appropriate counter value to all transactions
  ###

  transactions=$(echo "$transactions" | jq \
    --compact-output \
    --arg counter $current_counter \
    'to_entries | map(.value + {
      counter: (($counter|tonumber) + .key + 1)|tostring
    })'
  )


  ###
  ### Build operation JSON
  ###

  local operation_json=$(echo "{}" | jq \
    --compact-output \
    --argjson head $head_hash \
    --argjson transactions "$transactions" \
    '. + {
      branch: $head,
      contents: $transactions
    }'
  )


  ###
  ### Forge operation
  ###

  echo -n "  Forging operation... "
  local operation_bytes=$($CLIENT_CMD rpc post /chains/main/blocks/head/helpers/forge/operations with $operation_json)

  if ! rpcResponseOk "$operation_bytes" $?; then
    error "Could not forge transaction!" "$operation_json" "$operation_bytes"
  else
    operation_bytes=$(echo -n "$operation_bytes" | tr -d '"\r\n')
    echo "OK"
  fi


  ###
  ### Sign operation bytes
  ###

  echo -n "  Signing operation... "
  local ed_signature=""
  local tempfile=`mktemp`
  $CLIENT_CMD sign bytes 0x03$operation_bytes for $ACCOUNT_NAME | tee "$tempfile"
  local exit_code="${PIPESTATUS[0]}"
  local signing_response=$(cat "$tempfile")
  rm "$tempfile"
  if ! rpcResponseOk "$signing_response" $exit_code; then
    error "Invalid signing response!" "$signing_response"
  else
    ed_signature=$(echo -n "$signing_response" | extractRpcResponseField "Signature")
  fi
  if [[ $ed_signature == "" ]]; then
    error "Invalid signature generated!" "$signing_response"
  else
    echo "OK"
    log "Signature: $ed_signature"
  fi


  ###
  ### Generate signature bytes
  ###
  # signature bytes is odd because we need to chop off the prefix
  # bytes (which are [9, 245, 205, 134, 18] or 0x09F5CD8612 - the first 5 bytes)
  # but also (according to https://medium.com/@bakenrolls/sending-multiple-transactions-in-one-batch-using-tezos-rpc-6cab3a21f254)
  # the last 4 bytes, the reason for that I do not know...
  local decoded_signature_bytes=$(decodeBase58 $ed_signature)
  local trimmed_decoded_signature=$(echo -n $decoded_signature_bytes | awk '{print substr($0,11,length($0)-18)}' | tr '[:upper:]' '[:lower:]')


  ###
  ### Signed operation bytes + trimmed signature bytes = our final signed operation
  ###

  local signed_operation="$operation_bytes$trimmed_decoded_signature"


  ###
  ### Ensure the operation is valid with preapply
  ###

  echo -n "  Preapply/check operation... "
  local preapply_json=$(echo "{}" | jq \
    --compact-output \
    --argjson head $head_hash \
    --argjson transactions "$transactions" \
    --argjson protocol $protocol_hash \
    --arg signature $ed_signature \
    '[. + {
      branch: $head,
      contents: $transactions,
      protocol: $protocol,
      signature: $signature
    }]'
  )
  local preapply_response=$($CLIENT_CMD rpc post /chains/main/blocks/head/helpers/preapply/operations with $preapply_json)

  if ! rpcResponseOk "$preapply_response" $?; then
    error "Could not confirm operation as valid!" "$preapply_json" "$preapply_response"
  else
    preapply_response=$(cleanCr "$preapply_response")
    echo "OK"
    log "Preapply response: $preapply_response"
  fi


  ###
  ### Finally, inject the operation
  ###

  echo -n "  Injecting operation... "
  local injection_response=$($CLIENT_CMD rpc post /injection/operation with \"$signed_operation\")

  if ! rpcResponseOk "$injection_response" $?; then
    error "Could not inject operation!" "$signed_operation" "$injection_response"
  else
    injection_response=$(cleanCr "$injection_response")
    echo "OK"
  fi


  ###
  ### Wait for 1 confirmation
  ###

  echo -n "  Waiting for confirmation... "
  bash -c "$CLIENT_CMD wait for $injection_response to be included --confirmations 1 > /dev/null"
  if [ ! $? -eq 0 ]; then
    error "Confirmation failed!" "Check operation hash on tzscan or similar."
  else
    echo "OK"
  fi


  ###
  ### Note the operation hash so we can present all operations later
  ###

  OPERATION_HASHES+=($injection_response)
}


function main() {
  ###
  ### Simulate all transactions so we can be
  ### relatively sure they will succeed
  ###

  simulateTransactions "$TRANSACTIONS"


  ###
  ### Paginate the transactions in batches,
  ### the maximum operation size is 16k
  ###

  PAGE_SIZE=100
  CURRENT_OFFSET=0
  TRANSACTION_COUNT=$(echo -n "$TRANSACTIONS" | jq length)
  TOTAL_PAGES=$(pageNumber $TRANSACTION_COUNT $PAGE_SIZE)
  OPERATION_HASHES=()

  while true; do
    current_page=$(pageNumber $CURRENT_OFFSET $PAGE_SIZE)
    transactions=$(echo -n "$TRANSACTIONS" | jq \
      --exit-status \
      --argjson current $CURRENT_OFFSET \
      --argjson page_size $PAGE_SIZE \
      '
        .[$current:($current+$page_size)] as $page |
        if ($page | length) > 0 then $page else false end
      '
    )
    if [ $? -ne 0 ]; then
      echo
      echo "Operation Hashes:"
      for op_hash in "${OPERATION_HASHES[@]}"; do
        echo -e "  $(echo -n $op_hash | tr -d '"')"
      done
      echo
      break
    else
      echo
      echo "Sending transactions (page $((current_page+1)) of $TOTAL_PAGES)..."
      sendBatch "$transactions"
      CURRENT_OFFSET=$((CURRENT_OFFSET+PAGE_SIZE))
    fi
  done


  echo
  echo "DONE"
  echo

  if [ -z $RESTORE_DISCLAIMER ]; then
    export TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=$RESTORE_DISCLAIMER
  else
    unset TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER
  fi
}

checkDepsAndArgs
setup
main
