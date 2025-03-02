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
    filename="server-cloud-init.yaml"

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
    filename="agent-cloud-init.yaml"

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
    - curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" K3S_TOKEN=${K3S_TOKEN} sh -s - agent --server https://192.168.1.250:6443
EOM
    echo "Created $filename at $K3S_CONFIG_DIR" 
}


create_load_balancer_cloud_init() {
    template_path="./cloud-inits/loadbalancer-cloud-init.yaml"

    if [ ! -f "$template_path" ]; then
        echo "Error: Template file $template_path not found"
        exit 1
    fi

    nodes=$(kubectl --kubeconfig $K3S_CONFIG_DIR/config.yaml get nodes -o jsonpath='{range .items[?(@.metadata.labels.node-role\.kubernetes\.io/control-plane)]}{.metadata.name} {.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

    # Create a temporary file for modifications
    temp_file=$(mktemp)

    # Add server entries to the backend section
    awk '
    /backend k3s-backend/,/balance roundrobin/ {
        print
        if ($0 ~ /balance roundrobin/) {
            while (getline node < "/dev/stdin") {
                split(node, parts)
                printf "        server %s %s:6443 check\n", parts[1], parts[2]
            }
        }
        next
    }
    { print }
    ' "$template_path" <<< "$nodes" > "$temp_file"

    # Backup existing file if it exists
    filename="loadbalancer-cloud-init.yaml"
    output_path="${K3S_CONFIG_DIR}/$filename"
    if [ -f "$output_path" ]; then
        mv "$output_path" "${output_path}.bak"
    fi

    mv "$temp_file" "$output_path"
    echo "Created $filename at $K3S_CONFIG_DIR"
}
