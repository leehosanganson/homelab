#!/bin/bash

source ./cluster_config.sh
source ./check_commands.sh
source ./create_cloud_init.sh
source ./create_node.sh

check_required_tools

echo "Starting Cluster $CLUSTER_NAME"


# Create server-1 node
# If server-1 is already running, skip
if multipass info $CLUSTER_NAME-server-1 > /dev/null 2>&1; then
    echo "Server Node 1 is already running"
else
    create_master_cloud_init
    multipass launch --name $CLUSTER_NAME-server-1 --cpus $SERVER_CPU --memory $SERVER_MEM --disk $SERVER_DISK --cloud-init $K3S_CONFIG_DIR/$CLUSTER_NAME-master-server-cloud-init.yaml
fi

# Use server-1 kubeconfig as KUBECONFIG
multipass transfer $CLUSTER_NAME-server-1:/etc/rancher/k3s/k3s.yaml $K3S_CONFIG_DIR/$CLUSTER_NAME-kubeconfig.yaml
SERVER_IP=$(multipass info $CLUSTER_NAME-server-1 --format json | jq -r ".info.\"$CLUSTER_NAME-server-1\".ipv4[0]")
echo "Using $CLUSTER_NAME-server-1 at $SERVER_IP as K3S Server"
SERVER_URL="https://$SERVER_IP:6443"

sed -i.bak "/^[[:space:]]*server:/ s_:.*_: \"https://$(echo $SERVER_IP | sed -e 's/[[:space:]]//g'):6443\"_" $K3S_CONFIG_DIR/$CLUSTER_NAME-kubeconfig.yaml
KUBECONFIG=$K3S_CONFIG_DIR/$CLUSTER_NAME-kubeconfig.yaml

# Check if server-1 is Ready
check_server_node 1

K3S_TOKEN=$(multipass exec $CLUSTER_NAME-server-1 -- sudo cat /var/lib/rancher/k3s/server/node-token)

# # Create other server Nodes if needed
# if [ $SERVER_COUNT -gt 1 ]; then
#     create_server_cloud_init
#     for i in $(seq 2 $SERVER_COUNT); do
#         create_server_node $i
#         check_server_node $i
#     done
# fi

# Create Agent Nodes
for i in $(seq 1 $AGENT_COUNT); do
    if multipass info $CLUSTER_NAME-agent-$i > /dev/null 2>&1; then
        echo "Agent Node $i is already running"
    else
        create_agent_cloud_init
        create_agent_node $i
    fi
    check_agent_node $i
done

# Clean up cloud-init.yaml files
rm $K3S_CONFIG_DIR/$CLUSTER_NAME-master-server-cloud-init.yaml
rm $K3S_CONFIG_DIR/$CLUSTER_NAME-server-cloud-init.yaml
rm $K3S_CONFIG_DIR/$CLUSTER_NAME-agent-cloud-init.yaml

echo "k3s setup finished"
multipass exec $CLUSTER_NAME-server-1 -- sudo k3s kubectl get nodes

echo "Use the following commands to switch to the k3s context:"
echo "kubectl --kubeconfig ${K3S_CONFIG_DIR}/${CLUSTER_NAME}-kubeconfig.yaml get nodes"
