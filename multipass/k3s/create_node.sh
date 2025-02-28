#!/bin/bash

create_server_node() {
    local node_number=$1
    echo "Creating Server Node $node_number"
    multipass launch --name $CLUSTER_NAME-server-$node_number --cpus $SERVER_CPU --memory $SERVER_MEM --disk $SERVER_DISK --cloud-init $K3S_CONFIG_DIR/$CLUSTER_NAME-server-cloud-init.yaml
}

create_agent_node() {
    local node_number=$1
    echo "Creating Agent Node $node_number"
    multipass launch --name $CLUSTER_NAME-agent-$node_number --cpus $AGENT_CPU --memory $AGENT_MEM --disk $AGENT_DISK --cloud-init $K3S_CONFIG_DIR/$CLUSTER_NAME-agent-cloud-init.yaml
}

check_server_node() {
    local node_number=$1
    local max_attempts=10
    local sleep_time=5

    echo "Checking if Server Node $node_number is ready"
    
    for ((i=1; i<=max_attempts; i++)); do
        READY_NODES=$(kubectl --kubeconfig $KUBECONFIG get nodes --no-headers | grep -c "server-$node_number.*Ready")
        if [ $READY_NODES -eq 1 ]; then
            echo "Server Node $node_number is Ready"
            return 0
        fi
        echo "Attempt $i: Server Node $node_number not ready yet. Waiting $sleep_time seconds..."
        sleep $sleep_time
    done

    echo "Error: Server Node $node_number did not become Ready within the timeout period"
    return 1
}

check_agent_node() {
    local node_number=$1
    local max_attempts=10
    local sleep_time=5

    echo "Checking if Agent Node $node_number is ready"
    
    for ((i=1; i<=max_attempts; i++)); do
        READY_NODES=$(kubectl --kubeconfig $KUBECONFIG get nodes --no-headers | grep -c "agent-$node_number.*Ready")
        if [ $READY_NODES -eq 1 ]; then
            echo "Agent Node $node_number is Ready"
            return 0
        fi
        echo "Attempt $i: Agent Node $node_number not ready yet. Waiting $sleep_time seconds..."
        sleep $sleep_time
    done

    echo "Error: Agent Node $node_number did not become Ready within the timeout period"
    return 1
}
