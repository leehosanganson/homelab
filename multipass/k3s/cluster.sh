#!/bin/bash

source ./token.sh

check_cluster() {
  local cluster_name=$1

  # Check if kubeconfig file exists
  if [ ! -f "$K3S_CONFIG_DIR/config.yaml" ]; then
    echo "Kubeconfig file not found for cluster $cluster_name"
    return 1
  fi

  # Use kubectl to check if the cluster is running
  if ! timeout 5 kubectl --kubeconfig="$K3S_CONFIG_DIR/config.yaml" cluster-info &> /dev/null; then
    echo "Cluster $cluster_name is not running"
    return 1
  fi

  echo "Cluster $cluster_name is running"
  return 0
}

get_kubeconfig() {
  local cluster_name=$1

  if [ -z "$cluster_name" ]; then
    echo "Error: cluster_name is not set"
    return 1
  fi

  KUBECONFIG=$K3S_CONFIG_DIR/config.yaml

  if [ ! -f "$KUBECONFIG" ]; then
    echo "Error: Kubeconfig file not found for cluster $cluster_name"
    return 1
  fi

  echo "Using Kubeconfig file $KUBECONFIG"
  return 0
}


check_server_node_k3s_path() {
  local node_name=$1
  local max_attempts=1
  local sleep_time=5

  path="/etc/rancher/k3s"

  echo "Checking if ${path} directory exists on Server Node $node_name"

  for ((i=1; i<=max_attempts; i++)); do
    if multipass exec $node_name -- test -d $path; then
      echo "Server Node $node_name has the $path directory"
      return 0
    fi
    echo "Attempt $i: Server Node $node_name does not have the $path directory. Waiting $sleep_time seconds..."
    sleep $sleep_time
  done

  echo "Error: Server Node $node_name does not have the $path directory"
  return 1
}

get_server_url() {
  local cluster_name=$1
  
  # Get Server URL from KUBECONFIG
  SERVER_URL=$(sed -n 's/.*server: \(.*\).*/\1/p' $KUBECONFIG)

  echo "Server URL: $SERVER_URL"
  return 0
}
