#!/bin/bash
set -e

echo "Checking environment..."

OS_TYPE="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    OS_TYPE="windows"
fi

echo "Detected OS: $OS_TYPE"

install_ansible_linux() {
    if ! command -v ansible &> /dev/null; then
        echo "Ansible not found. Attempting to install..."
        if [ -f /etc/debian_version ]; then
            sudo apt-get update
            sudo apt-get install -y ansible python3-pip locales lsof unzip
            sudo locale-gen en_US.UTF-8
            sudo update-locale LANG=en_US.UTF-8
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y epel-release
            sudo yum install -y ansible unzip
        else
            echo "Unsupported Linux distribution for automatic Ansible installation. Please install Ansible manually."
            exit 1
        fi
    fi
    # Install psycopg2/psycopg2-binary for PostgreSQL modules
    if ! python3 -c "import psycopg2" 2>/dev/null; then
        echo "Installing psycopg2 for PostgreSQL support..."
        if [ -f /etc/debian_version ]; then
            # On Debian/Ubuntu, use apt to avoid externally-managed-environment error (PEP 668)
            sudo apt-get install -y python3-psycopg2 || echo "Warning: Could not install python3-psycopg2 via apt"
        else
            PIP_CMD=$(command -v pip3 || command -v pip || echo "")
            if [ -n "$PIP_CMD" ]; then
                $PIP_CMD install psycopg2-binary --break-system-packages 2>/dev/null || $PIP_CMD install psycopg2-binary || echo "Warning: Could not install psycopg2-binary via pip."
            else
                echo "Warning: pip not found. Please install psycopg2 manually."
            fi
        fi
    fi
}

install_ansible_windows() {
    if ! command -v ansible &> /dev/null; then
        echo "Ansible not found on Windows (Git Bash). Attempting to install via Pip..."
        if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
            echo "Pip not found. Please install Python and Pip first."
            exit 1
        fi
        PIP_CMD=$(command -v pip3 || command -v pip)
        $PIP_CMD install ansible
    fi
    # Install psycopg2-binary for PostgreSQL modules
    if ! python3 -c "import psycopg2" 2>/dev/null && ! python -c "import psycopg2" 2>/dev/null; then
        echo "Installing psycopg2-binary for PostgreSQL support..."
        PIP_CMD=$(command -v pip3 || command -v pip || echo "")
        if [ -n "$PIP_CMD" ]; then
            $PIP_CMD install psycopg2-binary || echo "Warning: Could not install psycopg2-binary via pip."
        else
            echo "Warning: pip not found. Please install psycopg2 manually with: pip install psycopg2-binary"
        fi
    fi
}

if [[ "$OS_TYPE" == "linux" ]]; then
    install_ansible_linux
elif [[ "$OS_TYPE" == "windows" ]]; then
    install_ansible_windows
else
    echo "Warning: OS type $OSTYPE is not explicitly supported for automatic Ansible installation."
    if ! command -v ansible &> /dev/null; then
        echo "Ansible not found. Please install it manually."
        exit 1
    fi
fi

echo "Ansible is ready. Proceeding with collections and prerequisites..."

# Install required collections
ansible-galaxy collection install ansible.windows community.windows chocolatey.chocolatey amazon.aws community.postgresql

# Install ansible-lint for development
if ! command -v ansible-lint &> /dev/null; then
    echo "Installing ansible-lint..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        if [ -f /etc/debian_version ]; then
            sudo apt-get install -y ansible-lint || echo "Warning: could not install ansible-lint via apt"
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y ansible-lint || echo "Warning: could not install ansible-lint via yum"
        fi
    elif [[ "$OS_TYPE" == "windows" ]]; then
        PIP_CMD=$(command -v pip3 || command -v pip || echo "")
        if [ -n "$PIP_CMD" ]; then
            $PIP_CMD install ansible-lint
        else
            echo "Warning: Could not find pip to install ansible-lint."
        fi
    fi
fi

# Install Python AWS dependencies for dynamic inventory support
echo "Installing python AWS dependencies (boto3, botocore)..."
PIP_CMD=$(command -v pip3 || command -v pip || echo "")
if [ -n "$PIP_CMD" ]; then
    $PIP_CMD install boto3 botocore --break-system-packages 2>/dev/null || $PIP_CMD install boto3 botocore || echo "Warning: Could not install boto3 and botocore via pip."
else
    echo "Warning: pip not found. Please install boto3 and botocore manually."
fi

echo "Prerequisites installed successfully."
