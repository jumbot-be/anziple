# APCM Deployment Ansible Repository

This repository contains Ansible roles and playbooks to deploy APCM components (Payara, Keycloak, NGINX) on both Linux (Ubuntu) and Windows Server environments.

## Prerequisites

### Control Node (Linux/macOS/Windows with Git Bash)
- Ansible 2.16+
- Run the setup script to install Ansible (if missing), collections, and `ansible-lint`:
  ```bash
  ./scripts/setup.sh
  ```

> **Note on Windows:** If you encounter `bad interpreter` errors when running the script, it might be due to CRLF line endings. Run `sed -i 's/\r$//' scripts/setup.sh` to fix it. It is recommended to configure git with `git config --global core.autocrlf input`.

### Managed Nodes
- **Linux:** SSH access, Python installed.
- **Windows:** WinRM must be configured. You can use the provided script as an Administrator to enable it:
  ```cmd
  scripts\setup_windows.bat
  ```

## Configuration

### Variables
Main configuration variables are located in `group_vars/all.yml`:
- `adr_base_path_linux`: Base installation directory for Linux (default: `/opt/adr`).
- `adr_base_path_windows`: Base installation directory for Windows (default: `C:\adr`).
- `artifacts`: A dictionary containing download URLs (or local paths) and SHA256 hashes for each component.
- `unattended_upgrades_enabled`: Install and enable `unattended-upgrades` for automatic security updates on Debian/Ubuntu hosts (default: `true`).

#### MongoDB kernel hold

`mongod` is incompatible with Linux kernel 6.19+ (TCMalloc/rseq crash). On Debian/Ubuntu database hosts, the `mongodb` role places all installed v6.x kernel packages (and their meta-packages) on `apt-mark hold` so that neither `apt upgrade` nor `unattended-upgrades` can pull an incompatible kernel. This is controlled by:

- `mongodb_kernel_hold_enabled`: Enable the kernel hold (default: `true`, see `roles/mongodb/defaults/main.yml`).
- `mongodb_kernel_v6_package_pattern` / `mongodb_kernel_meta_package_pattern`: Package name patterns that select the kernel packages to hold.

### Local vs Remote Sources
The roles automatically detect if an artifact source is a remote URL or a local file on the Ansible control node:
- **Remote:** Use `http://` or `https://`.
    - *SSL Verification:* If your server uses a self-signed certificate, add `validate_certs: false` to the artifact definition in `all.yml`.
- **Local:** Use a relative or absolute file path.
    - *Example (Linux):* `/home/user/sources/apcm-payara-bundle.zip`
    - *Example (Windows Git Bash):* `C:/sources/apcm-payara-bundle.zip` (Use forward slashes even on Windows for better compatibility with Git Bash and Ansible).

### Secrets and Ansible Vault
Sensitive information (passwords, keys) should be stored in `group_vars/all_secrets.yml`.

#### 1. Encrypting Secrets
To encrypt your secrets file for the first time:
```bash
ansible-vault encrypt group_vars/all_secrets.yml
```
You will be prompted for a password.

#### 2. Editing Secrets
To modify the encrypted file:
```bash
ansible-vault edit group_vars/all_secrets.yml
```

#### 3. Running with Vault
When running the playbook, you must provide the vault password:
```bash
ansible-playbook deploy.yml --ask-vault-pass
```
Alternatively, use a password file:
```bash
ansible-playbook deploy.yml --vault-password-file .vault_pass
```

## Deployment Procedure

### 1. Update Inventory
Edit `inventory/hosts.yml` to include your target servers.

### 2. Prepare Variables
Update `group_vars/all.yml` with the correct versions and artifact sources.

### 3. Run the Playbook
Execute the main deployment playbook:
```bash
# For remote deployment (requires SSH/WinRM access)
ansible-playbook -i inventory/hosts.yml deploy.yml --ask-vault-pass

# For local deployment (on the same machine where Ansible runs)
ansible-playbook -i inventory/hosts.yml deploy.yml --limit local --ask-vault-pass
```

## Multi-Server Deployment (Frontends & Backends)

The deployment architecture supports multi-server setups (e.g., a 2-server frontend/backend setup or a 3-tier setup) by utilizing specific host groups in your Ansible inventory.

### Host Groups

To partition components across multiple servers, group your hosts under the following children in your inventory file:

- **`frontend_servers`**: Hosts in this group will run frontend-facing services:
  - **NGINX** (Frontend configuration)
  - **Keycloak**
  - **Payara** (Frontend WARs)
- **`backend_servers`**: Hosts in this group will run background and core application services:
  - **Payara** (Backend WARs)
  - **MongoDB** (if a dedicated database group is not defined)
  - **PostgreSQL** (if a dedicated database group is not defined)
- **`database_servers`** *(Optional)*: Dedicated hosts for database engines. If defined:
  - **MongoDB** and **PostgreSQL** are deployed only on these hosts.
  - If omitted, database roles automatically fall back to deploying on `backend_servers`, and then to `all` hosts if `backend_servers` is also missing.

### Application Deployment Isolation (`payara_type`)

The `payara_type` variable specifies which application modules (WARs) are deployed and configured on each Payara server instance. Define this variable per host in your inventory to isolate services:

- **`payara_type: frontend`**: Deploys and configures only the frontend applications and web-related WARs.
- **`payara_type: backend`**: Deploys and configures only the backend components, APIs, and background processing WARs.
- **`payara_type: all`** *(Default)*: Deploys the complete stack of both frontend and backend WARs onto a single unified server.

### Multi-Server Inventory Example

Below is a concrete inventory example for a 2-server split deployment where `server-app-01` serves as the frontend layer and `server-db-01` serves as the database and backend layer:

```yaml
all:
  vars:
    # Set this to your internal network range for security
    allowed_network_range: "10.0.0.0/24"
    # MongoDB should bind to localhost and the internal IP
    mongodb_bind_ips: "127.0.0.1,10.0.0.2"

  children:
    frontend_servers:
      hosts:
        server-app-01:
          ansible_host: 10.0.0.1
          # payara_type controls which WARs are deployed (frontend/backend/all)
          payara_type: frontend

    backend_servers:
      hosts:
        server-db-01:
          ansible_host: 10.0.0.2
          payara_type: backend

    # If database_servers is not defined, roles fallback to backend_servers, then 'all'
    # database_servers:
    #   hosts:
    #     dedicated-db:
    #       ansible_host: 10.0.0.3
```

To run a multi-server deployment, pass your multi-server inventory file when executing the playbook:
```bash
ansible-playbook -i inventory/hosts.multi.yml deploy.yml --ask-vault-pass
```

## AWS Dynamic Inventory

To dynamically discover and manage AWS EC2 instances, you can use the AWS EC2 dynamic inventory configuration located in `inventory/aws_ec2_dev.yml`.

### Prerequisites
On your control node, you must install the AWS python dependencies (`boto3` and `botocore`):
```bash
pip install boto3 botocore
```
Additionally, ensure the `amazon.aws` collection is installed (it is installed automatically when running `./scripts/setup.sh`).

### Configuration
The inventory file `inventory/aws_ec2_dev.yml` is configured to:
- Retrieve instances across regions `eu-central-1` and `us-east-1`.
- Filter and retrieve **running** instances only (`instance-state-name: running`).
- Use the instance `Name` tag as the host name (falling back to private IP address).
- Use the **private IP address** for connecting (`ansible_host: private_ip_address`).

### Automatic OS & Connection Detection
The inventory dynamically assigns connection parameters in the `compose` section:
- If an instance platform is `'windows'` or its `OS` (or `os`) tag contains `'windows'`, it configures:
  - `ansible_connection: winrm`
  - `ansible_become: false`
  - `ansible_winrm_server_cert_validation: ignore`
- Otherwise (Linux instances), it configures:
  - `ansible_connection: ssh`
  - `ansible_become: true`

### Dynamic Grouping
To deploy APCM components correctly, instances must belong to standard Ansible host groups (`frontend_servers`, `backend_servers`, `database_servers`).
The `inventory/aws_ec2_dev.yml` contains examples under the `groups:` section that can be uncommented to assign EC2 instances to these groups based on their AWS `Role` tags.

### Usage

1. **Authentication:**
   Set your AWS credentials in your environment before running Ansible:
   ```bash
   export AWS_ACCESS_KEY_ID="your_access_key"
   export AWS_SECRET_ACCESS_KEY="your_secret_key"
   # Or use AWS profiles:
   export AWS_PROFILE="your_aws_profile"
   ```

2. **Verify Inventory:**
   List the discovered instances and their groupings to verify connection properties are computed correctly:
   ```bash
   ansible-inventory -i inventory/aws_ec2_dev.yml --graph
   # or
   ansible-inventory -i inventory/aws_ec2_dev.yml --list
   ```

3. **Run Playbooks:**
   Deploy to your AWS environment using the dynamic inventory:
   ```bash
   ansible-playbook -i inventory/aws_ec2_dev.yml deploy.yml --ask-vault-pass
   ```

### Troubleshooting & Warnings

If you encounter the following warning:
> `[WARNING]: Failed to parse inventory with 'auto' plugin: inventory source '...' could not be verified by inventory plugin 'amazon.aws.aws_ec2'`
> `[WARNING]: Unable to parse ... as an inventory source`

This is usually caused by:
1. **Missing `boto3` or `botocore` python libraries:** Ensure these libraries are installed on the control node in the Python environment that Ansible is executed from. Run:
   ```bash
   pip install boto3 botocore
   ```
2. **Missing `amazon.aws` collection:** Ensure the Ansible AWS collection is installed. Run:
   ```bash
   ansible-galaxy collection install amazon.aws
   ```
3. **Inventory plugin not enabled in `ansible.cfg`:** Ensure `amazon.aws.aws_ec2` is listed in the `enable_plugins` parameter inside the `[inventory]` section of your `ansible.cfg`. (This is already preconfigured in this repository's `ansible.cfg`).

## Version Management (Releases)

Component versions and file checksums are centralized in the `vars/releases/` folder. By default, the system uses the latest version defined in `group_vars/all.yml`.

To deploy or update to a specific version, use the `-e` option to include the corresponding release file:

```bash
ansible-playbook deploy.yml -e @vars/releases/4.0.9.yml --ask-vault-pass
```

### Automating Release Creation
A Python script is available to automatically generate release YAML files from a checksum list (`sha256sum` format). The script can automatically extract the version if the file is located in a directory named `ADR-X.Y.Z`.

```bash
# Recommended usage (extracts the version from the path and automatically defines the base-url)
python3 scripts/generate_release_vars.py /opt/SOURCES/ADR-4.0.10/checksums > vars/releases/4.0.10.yml

# Usage with redirection (stdin)
cat checksums.txt | python3 scripts/generate_release_vars.py > vars/releases/3.3.1.yml
```

### Keycloak Flavors
The system supports two Keycloak distributions: Standard and Red Hat (RH).
- `keycloak_flavor: "rh"` (default): Uses the Red Hat bundle.
- `keycloak_flavor: "standard"`: Uses the standard bundle.

This variable can be defined in `group_vars/all.yml` or passed via the command line with `-e "keycloak_flavor=standard"`.

## Update Procedure

The update system is modular, allowing either a complete update or a targeted update. All main playbooks are located in the `playbook/` directory.

### 1. Full Update
To update all components (JDK, Databases, Applications):
```bash
ansible-playbook update.yml --ask-vault-pass
```
*(This playbook calls `playbook/update_all.yml`)*

### 2. Targeted Component Update
Each component has its own playbook that manages its dependencies (e.g., PostgreSQL backup for Keycloak).

```bash
# Examples of targeted updates
ansible-playbook playbook/update_keycloak.yml --ask-vault-pass
ansible-playbook playbook/update_payara.yml --ask-vault-pass
ansible-playbook playbook/update_postgresql.yml --ask-vault-pass
```

### 3. Modular Operations
Each application role now contains separate tasks in `tasks/`:
- `stop.yml`: Stops the service.
- `start.yml`: Starts the service.
- `update.yml`: Full update cycle (Stop -> Backup -> Dependencies -> Installation -> Start).

## Administration and Maintenance

Other maintenance playbooks are available in `playbook/`:
- **cleanup.yml**: Cleans up temporary files.
- **deinstall.yml**: Uninstalls components.

Example: `ansible-playbook cleanup.yml --ask-vault-pass`

## Role Structure
- **common**: Installs Zulu JDK and configures system paths (and Git Bash on Windows).
- **integrity**: Reusable task to download/copy artifacts and verify SHA256 integrity.
- **keycloak / payara / nginx**: Handles extraction, configuration (templating `config.properties`), and execution of mandatory scripts (`[1-9]-*`).

## Script Conventions
The roles automatically find and execute mandatory scripts in numerical order:
1. `prepare-config.sh` (always executed first).
2. Any script matching `[1-9]*-bundle-name--*.sh` in the bundle root.




ansible-playbook -i inventory/hosts.yml --limit=localhost deploy.yml -e @vars/releases/4.0.10.yml
