#!/bin/bash

# Function to check if a command is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
check_required_tools() {
    required_tools=("multipass" "jq" "curl" "sed")
    missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: The following required tools are missing:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo "Please install these tools before running this script."
        echo "Installation instructions:"
        echo "  - multipass: https://multipass.run/"
        echo "  - jq: https://stedolan.github.io/jq/download/"
        echo "  - curl: Usually pre-installed, or use your system's package manager"
        echo "  - sed: Usually pre-installed, or use your system's package manager"
        exit 1
    fi

    echo "All required tools are available. Proceeding with cluster setup..."
}
