#!/bin/bash

create_master_cloud_init() {
    mkdir -p $K3S_CONFIG_DIR
    cat > $K3S_CONFIG_DIR/$CLUSTER_NAME-master-server-cloud-init.yaml << EOM
#cloud-config
ssh_authorized_keys:
    - $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
    - git
    - vim
    - tmux

runcmd:
    - curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="server" sh -
EOM

    echo "Created $CLUSTER_NAME-master-server-cloud-init.yaml at $K3S_CONFIG_DIR"
}

# create_server_cloud_init() {
#     mkdir -p $K3S_CONFIG_DIR
#     cat > $K3S_CONFIG_DIR/$CLUSTER_NAME-server-cloud-init.yaml << EOM
# #cloud-config
# ssh_authorized_keys:
#     - $(cat ~/.ssh/id_rsa.pub)
#
# package_update: true
#
# packages:
#     - git
#     - vim
#     - tmux
#
# runcmd:
#     - curl -sfL https://get.k3s.io | sh -s - server --server $K3S_URL:6443 --token $K3S_TOKEN
# EOM
#
#     echo "Created $CLUSTER_NAME-server-cloud-init.yaml at $K3S_CONFIG_DIR" 
# }

create_agent_cloud_init() {
    mkdir -p $K3S_CONFIG_DIR
    cat > $K3S_CONFIG_DIR/$CLUSTER_NAME-agent-cloud-init.yaml << EOM
#cloud-config
ssh_authorized_keys:
    - $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
    - git
    - vim
    - tmux

runcmd:
    - curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN K3S_URL=$SERVER_URL K3S_KUBECONFIG_MODE=644 sh -
EOM
    echo "Created $CLUSTER_NAME-agent-cloud-init.yaml at $K3S_CONFIG_DIR" 
}
