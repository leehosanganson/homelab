#!/bin/bash

create_server_cloud_init() {
    # Check if the parameter is set to init cluster
    INIT_CLUSTER_FLAG=""
    SERVER_URL_FLAG=""
    token=""

    if [ "$1" == "cluster" ]; then
        INIT_CLUSTER_FLAG=" --cluster-init"
        token=$SERVER_TOKEN
    fi

    # if parameter is not 'init', check if the Server URL is set
    if [ "$1" != "cluster" ]; then
        if [ -z "$SERVER_URL" ]; then
            echo "Error: Server URL is not set."
            exit 1
        fi
        SERVER_URL_FLAG=" --server $SERVER_URL"
        token=$K3S_TOKEN
    fi

    mkdir -p $K3S_CONFIG_DIR
    filename="$CLUSTER_NAME-server-cloud-init.yaml"

    # If the file already exists, back it up
    if [ -f $K3S_CONFIG_DIR/$filename ]; then
        mv $K3S_CONFIG_DIR/$filename $K3S_CONFIG_DIR/$filename.bak
    fi

    cat > $K3S_CONFIG_DIR/$filename << EOM
#cloud-config
ssh_authorized_keys:
    - $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
    - git
    - vim
    - tmux

runcmd:
    - curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" K3S_TOKEN=${token} sh -s - server${INIT_CLUSTER_FLAG}${SERVER_URL_FLAG}
EOM

    echo "Created $filename at $K3S_CONFIG_DIR"
}

create_agent_cloud_init() {
    if [ -z "$SERVER_URL" ]; then
        echo "Error: Server URL is not set."
        exit 1
    fi

    if [ -z "$K3S_TOKEN" ]; then
        echo "Error: K3S Token is not set."
        exit 1
    fi

    mkdir -p $K3S_CONFIG_DIR
    filename="$CLUSTER_NAME-agent-cloud-init.yaml"

    # If the file already exists, back it up
    if [ -f $K3S_CONFIG_DIR/$filename ]; then
        mv $K3S_CONFIG_DIR/$filename $K3S_CONFIG_DIR/$filename.bak
    fi

    cat > $K3S_CONFIG_DIR/$filename << EOM
#cloud-config
ssh_authorized_keys:
    - $(cat ~/.ssh/id_rsa.pub)

package_update: true

packages:
    - git
    - vim
    - tmux

runcmd:
    - curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" K3S_TOKEN=${K3S_TOKEN} sh -s - agent --server ${SERVER_URL}
EOM
    echo "Created $filename at $K3S_CONFIG_DIR" 
}
