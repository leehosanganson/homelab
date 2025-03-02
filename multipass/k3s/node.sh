#!/bin/bash

create_server_node() {
    local node_name=$1
    echo "Creating Server Node $node_name"
    multipass launch --name $node_name ---bridged -cpus $SERVER_CPU --memory $SERVER_MEM --disk $SERVER_DISK --cloud-init $K3S_CONFIG_DIR/server-cloud-init.yaml
}

create_agent_node() {
    local node_name=$1
    echo "Creating Agent Node $node_name"
    multipass launch --name $node_name --bridged --cpus $AGENT_CPU --memory $AGENT_MEM --disk $AGENT_DISK --cloud-init $K3S_CONFIG_DIR/agent-cloud-init.yaml
}

create_load_balancer_node() {
    local node_name=$1
    echo "Creating Load Balancer Node $node_name"
    multipass launch --name $node_name --bridged --cpus $LOAD_BALANCER_CPU --memory $LOAD_BALANCER_MEM --disk $LOAD_BALANCER_DISK --cloud-init $K3S_CONFIG_DIR/loadbalancer-cloud-init.yaml
}

check_node() {
    local node_name=$1
    local max_attempts=3
    local sleep_time=5

    echo "Checking if Node $node_name is ready"
    
    for ((i=1; i<=max_attempts; i++)); do
        READY_NODES=$(kubectl --kubeconfig $KUBECONFIG get nodes --no-headers | grep -c "$node_name.*Ready")
        if [ $READY_NODES -eq 1 ]; then
            echo "Server Node $node_name is Ready"
            return 0
        fi
        echo "Attempt $i: Node $node_name not ready yet. Waiting $sleep_time seconds..."
        sleep $sleep_time
    done

    echo "Error: Server Node $node_name did not become Ready within the timeout period"
    return 1
}
