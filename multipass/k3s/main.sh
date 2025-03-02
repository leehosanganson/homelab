#!/bin/bash

source ./config.sh
source ./check_commands.sh
source ./cloud_init.sh
source ./node.sh
source ./cluster.sh
source ./token.sh

check_required_tools

K3S_CONFIG_DIR="$HOME/.kube/$CLUSTER_NAME"
mkdir -p $K3S_CONFIG_DIR

# Check if the cluster already exists
if ! check_cluster $CLUSTER_NAME; then
    echo "Creating Cluster $CLUSTER_NAME"

    SERVER_TOKEN=$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    create_server_cloud_init cluster

    node_name=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 4 | head -n 1)
    node_full_name="$CLUSTER_NAME-server-$node_name"

    create_server_node "$node_full_name"
    
    if ! check_server_node_k3s_path $node_full_name; then
        echo "Unable to find the '/etc/rancher/k3s' directory on the server node. Please check the cloud-init logs for the server node."
        return 1
    fi

    # Transfer kubeconfig file to local
    multipass transfer $node_full_name:/etc/rancher/k3s/k3s.yaml $K3S_CONFIG_DIR/config.yaml
    SERVER_IP=$(multipass info $node_full_name --format json | jq -r ".info.\"$node_full_name\".ipv4[0]")
    sed -i.bak "/^[[:space:]]*server:/ s_:.*_: https://$(echo $SERVER_IP | sed -e 's/[[:space:]]//g'):6443_" $K3S_CONFIG_DIR/config.yaml
    echo "Using $node_full_name at $SERVER_IP as primary K3S Server / load balancer"
    KUBECONFIG=$K3S_CONFIG_DIR/config.yaml

    check_node $node_full_name

    # Save Token to File
    K3S_TOKEN=$(multipass exec $node_full_name -- sudo cat /var/lib/rancher/k3s/server/node-token)
    echo $K3S_TOKEN > $K3S_TOKEN_DIR
fi

get_kubeconfig $CLUSTER_NAME
get_server_url $CLUSTER_NAME
get_token

# Create Server Nodes
if [ $SERVER_COUNT -gt 0 ]; then
    create_server_cloud_init
    for i in $(seq 1 $SERVER_COUNT); do
        node_name=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 4 | head -n 1)
        node_full_name="$CLUSTER_NAME-server-$node_name"
        create_server_node "$node_full_name"
        check_node "$node_full_name"
    done
fi

# Create Load Balancer Nodes
if [ $LOAD_BALANCER_COUNT -gt 0 ]; then
    create_load_balancer_cloud_init
    for i in $(seq 1 $LOAD_BALANCER_COUNT); do
        node_name=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 4 | head -n 1)
        node_full_name="$CLUSTER_NAME-lb-$node_name"
        create_load_balancer_node "$node_full_name"
    done
fi

# Create Agent Nodes
if [ $AGENT_COUNT -gt 0 ]; then
    create_agent_cloud_init
    for i in $(seq 1 $AGENT_COUNT); do
        node_name=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 4 | head -n 1)
        node_full_name="$CLUSTER_NAME-agent-$node_name"
        create_agent_node "$node_full_name"
        check_node "$node_full_name"
    done
fi

echo "k3s setup finished"
kubectl --kubeconfig ${K3S_CONFIG_DIR}/config.yaml get nodes

echo "Use the following commands to switch to the k3s context:"
echo "kubectl --kubeconfig ${K3S_CONFIG_DIR}/config.yaml get nodes"
