#!/bin/bash

create_server_node() {
    local node_number=$1
    echo "Creating Server Node $node_number"
    multipass launch --name $CLUSTER_NAME-server-$node_number --cpus $SERVER_CPU --mem $SERVER_MEM --disk $SERVER_DISK --cloud-init $CLUSTER_NAME-cloud-init.yaml
}

check_server_node() {
    local node_number=$1
    echo "Checking if Server Node $node_number is ready"
    IP=$(multipass info $CLUSTER_NAME-server-$node_number --format json | jq -r '.ipv4[0]')
    if [ -z "$IP" ]; then
        echo "Error: Could not retrieve IP for Server Node $node_number"
        exit 1
    fi
    if timeout 300 bash -c "until curl -sfL -k https://$IP:6443/healthz &>/dev/null; do sleep 5; done"; then
        echo "Server Node $node_number is ready"
    else
        echo "Error: Server Node $node_number did not become ready within the timeout period"
        exit 1
    fi
}

create_agent_node() {
    local node_number=$1
    echo "Creating Agent Node $node_number"
    multipass launch --name $CLUSTER_NAME-agent-$node_number --cpus $AGENT_CPU --mem $AGENT_MEM --disk $AGENT_DISK --cloud-init $CLUSTER_NAME-agent-cloud-init.yaml
}

check_agent_node() {
    local node_number=$1
    IP=$(multipass info $CLUSTER_NAME-agent-$node_number --format json | jq -r '.ipv4[0]')
    if [ -z "$IP" ]; then
        echo "Error: Could not retrieve IP for Agent Node $node_number"
        exit 1
    fi

    echo "Checking for Node $CLUSTER_NAME-agent-$node_number being registered"
    timeout 300 multipass exec $CLUSTER_NAME-server-1 -- bash -c "until sudo k3s kubectl get nodes --no-headers | grep -c $CLUSTER_NAME-agent-$node_number >/dev/null 2>&1; do sleep 2; done"

    echo "Checking for Node $CLUSTER_NAME-agent-$node_number being Ready"
    timeout 300 multipass exec $CLUSTER_NAME-server-1 -- bash -c "until sudo k3s kubectl get nodes --no-headers | grep $CLUSTER_NAME-agent-$node_number | grep -c -v NotReady >/dev/null 2>&1; do sleep 2; done"

    echo "Node $CLUSTER_NAME-agent-$node_number is Ready on $CLUSTER_NAME"
}
