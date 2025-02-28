#!/bin/bash

source ./cluster_config.sh
source ./check_commands.sh
source ./create_cloud_init.sh
source ./create_node.sh

if ! check_required_tools; then
    echo "Some required tools are not installed. Please install them and try again."
    exit 1
fi

echo "Starting Cluster $CLUSTER_NAME"

# Create Tokens
SERVER_TOKEN=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 20 | head -n 1)
AGENT_TOKEN=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 20 | head -n 1)

create_master_cloud_init

# Create server-1 node
multipass launch --name $CLUSTER_NAME-server-1 --cpus $SERVER_CPU --mem $SERVER_MEM --disk $SERVER_DISK --cloud-init $CLUSTER_NAME-cloud-init.yaml

# Check if server-1 is ready
SERVER_IP=$(multipass info $CLUSTER_NAME-server-1 --format json | jq -r '.ipv4[0]')
URL="https://$SERVER_IP:6443"

if timeout 300 bash -c "while ! curl -sfL -k https://$SERVER_IP:6443/healthz; do sleep 5; done"; then
    echo "Server Node 1 is ready"
else
    echo "Error: Server Node 1 did not become ready within the timeout period"
    exit 1
fi

# Create other server Nodes if needed
if [ $SERVER_COUNT -gt 1 ]; then
    create_server_cloud_init
    for i in $(seq 2 $SERVER_COUNT); do
        create_server_node $i
        check_server_node $i
    done
fi

# Create Agent Nodes
create_agent_cloud_init
for i in $(seq 1 $AGENT_COUNT); do
    create_agent_node $i
    check_agent_node $i
done

# K3S configs
multipass copy-files $CLUSTER_NAME-server-1:/etc/rancher/k3s/k3s.yaml $CLUSTER_NAME-kubeconfig-orig.yaml
sed "/^[[:space:]]*server:/ s_:.*_: \"https://$(echo $SERVER_IP | sed -e 's/[[:space:]]//g'):6443\"_" $CLUSTER_NAME-kubeconfig-orig.yaml > $CLUSTER_NAME-kubeconfig.yaml

# Clean up cloud-init.yaml files
rm $CLUSTER_NAME-master-server-cloud-init.yaml
rm $CLUSTER_NAME-server-cloud-init.yaml
rm $CLUSTER_NAME-agent-cloud-init.yaml

echo "k3s setup finished"
multipass exec $CLUSTER_NAME-server-1 -- sudo k3s kubectl get nodes

echo "Use the following commands to switch to the k3s context:"
echo "kubectl --kubeconfig ${CLUSTER_NAME}-kubeconfig.yaml get nodes"
