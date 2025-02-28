#!/bin/bash

create_master_cloud_init() {
    cat > $CLUSTER_NAME-master-server-cloud-init.yaml << EOM
#cloud-config

ssh_authorized_keys:
  - $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
  - git
  - vim
  - tmux

runcmd:
 - '\curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="stable" K3S_TOKEN=$SERVER_TOKEN K3S_AGENT_TOKEN=$AGENT_TOKEN INSTALL_K3S_EXEC="server --cluster-init" K3S_KUBECONFIG_MODE=644 sh -'
EOM

    echo "Created $CLUSTER_NAME-master-server-cloud-init.yaml"
}

create_server_cloud_init() {
    cat > $CLUSTER_NAME-server-cloud-init.yaml << EOM
#cloud-config

ssh_authorized_keys:
- $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
- git
- vim
- tmux

runcmd:
- '\curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="stable" K3S_TOKEN=$SERVER_TOKEN K3S_AGENT_TOKEN=$AGENT_TOKEN INSTALL_K3S_EXEC="server --server $URL" K3S_KUBECONFIG_MODE=644 sh -'
EOM

    echo "Created $CLUSTER_NAME-server-cloud-init.yaml" 
}

create_agent_cloud_init() {
    cat > $CLUSTER_NAME-agent-cloud-init.yaml << EOM
#cloud-config

ssh_authorized_keys:
- $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
- git
- vim
- tmux

runcmd:
- '\curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="stable" K3S_TOKEN=$AGENT_TOKEN K3S_URL=$URL K3S_KUBECONFIG_MODE=644 sh -'
EOM
    echo "Created $CLUSTER_NAME-agent-cloud-init.yaml" 
}
