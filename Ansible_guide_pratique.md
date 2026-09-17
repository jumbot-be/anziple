# Guide pratique Ansible

## Architecture

Deploymatic deploie APCM sur Linux (Ubuntu) et Windows Server via Ansible.

**Components**
- Keycloak (authentification)
- Payara (applications Java EE)
- NGINX (reverse proxy)
- PostgreSQL (base de donnees relationnelle)
- MongoDB (base de donnees NoSQL)
- Postfix (relai SMTP)
- Zabbix (monitoring)

**Groupes de serveurs**
- `frontend_servers`: NGINX, Keycloak, Payara (WARs frontend)
- `backend_servers`: NGINX, Payara (WARs backend), MongoDB, PostgreSQL
- `database_servers`: MongoDB, PostgreSQL (optionnel, sinon bascule sur backend_servers)

**Types Payara**
- `frontend`: WARs frontend uniquement
- `backend`: WARs backend uniquement  
- `all`: tous les WARs (defaut)

---

## Pre-requis

### Noeud de controle (ou run local)
- Ansible 2.16+
- Collections: `ansible.windows`, `community.windows`, `chocolatey.chocolatey`

**Installation rapide**
```bash
./scripts/setup.sh
```

**Windows (Git Bash)**
```cmd
scripts\setup_windows.bat
```

**Noeuds geres**
- Linux: SSH + Python
- Windows: WinRM configure (setup_windows.bat en admin)

---

## Configuration

### 1. Inventaire

Fichier: `inventory/hosts.yml`

**Exemple mono-serveur**
```yaml
all:
  children:
    linux:
      vars:
        ansible_become: true
      hosts:
        serveur-01:
          ansible_host: 192.168.1.10
    local:
      hosts:
        localhost:
          ansible_connection: local
```

**Exemple multi-serveurs**
```yaml
all:
  vars:
    allowed_network_range: "10.0.0.0/24"
    mongodb_bind_ips: "127.0.0.1,10.0.0.2"
  children:
    frontend_servers:
      hosts:
        front-01:
          ansible_host: 10.0.0.1
          payara_type: frontend
    backend_servers:
      hosts:
        back-01:
          ansible_host: 10.0.0.2
          payara_type: backend
    database_servers:
      hosts:
        db-01:
          ansible_host: 10.0.0.3
```

### 2. Variables principales

Fichier: `group_vars/all.yml`

Variables a adapter:
```yaml
adr_base_path_linux: "/opt/adr"
adr_base_path_windows: 'C:\adr'

# Reseau
allowed_network_range: "127.0.0.1/32"
mongodb_bind_ips: "127.0.0.1"

# Version par defaut
include_release_vars: "vars/releases/4.0.9.yml"

# Postfix (relai SMTP)
postfix_relay_host: "smtp.example.com"
postfix_relay_port: "587"
postfix_relay_user: "user@example.com"
postfix_relay_password: "password"
postfix_from_address: "deploy@example.com"

# Client PostgreSQL (si DB sur serveur dedie)
postgresql_host: "10.0.0.3"
```

### 3. Secrets

Fichier: `group_vars/all_secrets.yml` (a chiffrer avec Ansible Vault)

```yaml
keycloak_admin_password: "admin"
payara_admin_password: "admin"
postgresql_admin_password: "StrongAdminPassword123!"
postgresql_adr_keycloak_password: "StrongKeycloakPassword123!"
postgresql_adr_customer_password: "StrongAdrCustomerPassword123!"
```

**Chiffrement**
```bash
ansible-vault encrypt group_vars/all_secrets.yml
ansible-vault edit group_vars/all_secrets.yml
```

### 4. Sources des artefacts

Fichier: `vars/releases/X.Y.Z.yml`

**Local** (chemins absolus ou relatifs au noeud de controle)
```yaml
artifacts:
  payara:
    url: "/opt/SOURCES/apcm-payara-bundle-5.82.0-4.0.8-payara-bundle.zip"
    checksum: "sha256:352e72d4e493d4f06f121ed7ee14888a8c3d3938d71fe1a6938bd3b6fcc8bbbd"
```

**Remote** (URL HTTP/HTTPS)
```yaml
artifacts:
  payara:
    url: "https://example.com/downloads/apcm-payara-bundle-5.82.0-4.0.8-payara-bundle.zip"
    checksum: "sha256:352e72d4e493d4f06f121ed7ee14888a8c3d3938d71fe1a6938bd3b6fcc8bbbd"
    validate_certs: false  # si certificat auto-signe
```

---

## Deployment

### Commande de base

```bash
ansible-playbook -i inventory/hosts.yml deploy.yml --ask-vault-pass
```

### Options courantes

**Cibler un serveur**
```bash
ansible-playbook deploy.yml --limit front-01 --ask-vault-pass
```

**Deployment local**
```bash
ansible-playbook -i inventory/hosts.yml deploy.yml --limit local --ask-vault-pass
```

**Version specifique**
```bash
ansible-playbook deploy.yml -e @vars/releases/4.0.10.yml --ask-vault-pass
```

**Fichier de mot de passe Vault**
```bash
ansible-playbook deploy.yml --vault-password-file .vault_pass
```

**Verifier la configuration**
```bash
ansible-playbook deploy.yml --check --ask-vault-pass
```

---

## Mise a jour

### Mise a jour complete

```bash
ansible-playbook update.yml --ask-vault-pass
```

### Mise a jour par composant

```bash
ansible-playbook playbook/update_keycloak.yml --ask-vault-pass
ansible-playbook playbook/update_payara.yml --ask-vault-pass
ansible-playbook playbook/update_postgresql.yml --ask-vault-pass
ansible-playbook playbook/update_mongodb.yml --ask-vault-pass
ansible-playbook playbook/update_nginx.yml --ask-vault-pass
```

---

## Maintenance

### Nettoyage

```bash
ansible-playbook cleanup.yml --ask-vault-pass
```

### Desinstallation

```bash
ansible-playbook deinstall.yml --ask-vault-pass
```

### Desinstallation par composant (not implemented yet)

```bash
ansible-playbook playbook/deinstall_component.yml -e "component=keycloak" --ask-vault-pass
```

---

## Gestion des versions

### Creer un fichier de release

A partir d'un fichier checksums (format `sha256sum`):
```bash
python3 scripts/generate_release_vars.py /opt/SOURCES/ADR-4.0.10/checksums > vars/releases/4.0.10.yml
```

A partir de stdin:
```bash
cat checksums.txt | python3 scripts/generate_release_vars.py > vars/releases/4.0.11.yml
```

---

## Extra

### Keycloak Flavors

```bash
ansible-playbook deploy.yml -e "keycloak_flavor=standard" --ask-vault-pass
# ou
ansible-playbook deploy.yml -e "keycloak_flavor=rh" --ask-vault-pass
```

### Tags Ansible

Lister les tags disponibles:
```bash
ansible-playbook deploy.yml --list-tags
```

Executer un tag specifique:
```bash
ansible-playbook deploy.yml --tags "nginx" --ask-vault-pass
```

### Debug

Afficher les variables d'un host:
```bash
ansible localhost -m debug -a "var=hostvars[inventory_hostname]" --ask-vault-pass
```

---

## Structure du projet

```
.
├── ansible.cfg              # Configuration Ansible
├── deploy.yml               # Playbook principal (import playbook/deploy.yml)
├── update.yml               # Mise a jour complete
├── cleanup.yml              # Nettoyage
├── deinstall.yml            # Desinstallation
├── inventory/
│   ├── hosts.yml            # Inventaire par defaut
│   ├── hosts.multi.example.yml  # Exemple multi-serveurs
│   └── frontend.yml         # Exemple frontend
├── group_vars/
│   ├── all.yml              # Variables globales
│   └── all_secrets.yml      # Secrets (a chiffrer)
├── vars/
│   └── releases/
│       ├── 3.1.1.yml        # Version 3.1.1
│       ├── 4.0.9.yml        # Version 4.0.9
│       └── 4.0.10.yml       # Version 4.0.10
├── roles/
│   ├── common/              # JDK, configurations systeme
│   ├── cleanup/             # Nettoyage
│   ├── deinstall/           # Desinstallation
│   ├── integrity/           # Verification checksums
│   ├── keycloak/            # Keycloak
│   ├── mongodb/             # MongoDB
│   ├── nginx/               # NGINX
│   ├── payara/              # Payara
│   ├── postfix/             # Postfix
│   ├── postgresql/          # PostgreSQL
│   └── zabbix/              # Zabbix
├── playbook/
│   ├── deploy.yml           # Deployment real
│   ├── update_all.yml       # Mise a jour complete
│   ├── update_keycloak.yml  # Mise a jour Keycloak
│   ├── update_mongodb.yml   # Mise a jour MongoDB
│   ├── update_nginx.yml     # Mise a jour NGINX
│   ├── update_payara.yml    # Mise a jour Payara
│   ├── update_postgresql.yml # Mise a jour PostgreSQL
│   ├── cleanup.yml          # Nettoyage real
│   └── deinstall.yml        # Desinstallation real
└── scripts/
    ├── setup.sh             # Setup Linux
    ├── setup_windows.bat    # Setup Windows
    ├── generate_release_vars.py  # Generation release
    ├── remove_java_config.sh     # Nettoyage config Java
    └── create_ampacimon_structure.ps1  # Structure PowerShell
```

---

## Depannage

**Erreur WinRM sur Windows**
- Executer `scripts\setup_windows.bat` en admin sur le serveur cible
- Verifier `ansible_winrm_server_cert_validation: ignore` dans l'inventaire

**Erreur CRLF**
```bash
sed -i 's/\r$//' scripts/setup.sh
```

**Verifier la connectivite**
```bash
ansible all -m ping
```
