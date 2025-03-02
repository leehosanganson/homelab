#!/bin/bash

get_token() {
  K3S_TOKEN_DIR=$K3S_CONFIG_DIR/token.txt

  if [ -f $K3S_TOKEN_DIR ]; then
    K3S_TOKEN=$(cat $K3S_TOKEN_DIR)
    if [ -z "$K3S_TOKEN" ]; then
      echo "Error: K3S Token ${CLUSTER_NAME}-token.txt is empty."
      return 1
    fi
    return 0
  fi
  
  echo "Error: K3S Token ${CLUSTER_NAME}-token.txt not found in ${K3S_TOKEN_DIR}."
  return 1
}
