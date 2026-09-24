# Migration NGINX : Remplacement des Scripts par Ansible

## 📋 Contexte

Le déploiement NGINX actuel utilise une **architecture complexe** basée sur :
- Des **bundles** contenant des scripts shell (`prepare-config.sh`, `1-nginx--setup.sh`, etc.)
- **Apache Ant** pour le filtrage de tokens (`@variable@`)
- Des **fichiers de configuration statiques** dans `TMP-CONFIG/`
- Des **scripts interactifs** demandant confirmation à l'utilisateur

**Objectif** : Remplacer cette approche par du **templating Jinja2 direct** et des **tâches Ansible**, tout en conservant la même structure de fichiers et les mêmes fonctionnalités.

---

## 🔍 Analyse des Composants Actuels

### Structure du Bundle NGINX

```
apcm-nginx-bundle/
├── prepare-config.sh          # Appelle Ant pour filtrer les tokens @...@
├── build.xml                  # Définition des tâches Ant
├── profiles/
│   └── template/
│       └── config.properties  # Variables par défaut (key=value)
└── resources/                # Fichiers templates avec tokens @...@
    ├── config/nginx/
    │   ├── sites-enabled/ampacimon.conf
    │   ├── conf/nginx.conf
    │   ├── apcm-config/*.config
    │   └── apcm-shared/*.shared
    ├── static/               # favicon.ico, index.html, error.html
    └── scripts/bash/
        ├── _copy_config.sh      # Copie les fichiers de config
        ├── _copy_static.sh       # Copie les fichiers statiques
        ├── _setup_certificate.sh # Configure les certificats SSL
        └── cron/
            └── _create-cronjob.sh # Crée les tâches cron pour les logs
```

### Mécanisme de Filtrage (Ant)

1. `prepare-config.sh ansible` → `ant -Dprofile=ansible`
2. Ant exécute `build.xml`:
   - Copie les binaires (.ico, .woff, .zip) → `generated/` **sans filtrage**
   - Charge `profiles/ansible/config.properties` comme filtre
   - Copie TOUS les autres fichiers → `generated/` **AVEC filtrage** (remplace `@token@`)

### Tokens Identifiés

| Token | Variable Ansible | Description |
|-------|------------------|-------------|
| `@nginx.config.name@` | `nginx_config_name` | Nom de la configuration (ex: ampacimon) |
| `@keycloak.host.fqdn@` | `keycloak_host_fqdn` | FQDN de Keycloak |
| `@keycloak.https.port@` | `keycloak_https_port` | Port HTTPS de Keycloak |
| `@keycloak.https.managementport@` | `keycloak_management_port` | Port de management Keycloak |
| `@adr.server.host.fqdn@` | `adr_server_host_fqdn` | FQDN du backend ADR |
| `@adr.server.https.port@` | `adr_server_https_port` | Port HTTPS du backend |
| `@adr.front.host.fqdn@` | `adr_front_host_fqdn` | FQDN du frontend ADR |
| `@adr.front.https.port@` | `adr_front_https_port` | Port HTTPS du frontend |
| `@facility.front.host.fqdn@` | `facility_front_host_fqdn` | FQDN Facility Ratings |
| `@facility.front.https.port@` | `facility_front_https_port` | Port Facility Ratings |
| `@ext.host.fqdn@` | `ext_host_fqdn` | FQDN externe |
| `@static.files.folder@` | `static_files_folder` | Dossier des fichiers statiques |
| `@nginx.home.directory@` | `nginx_home_directory` | Répertoire racine NGINX |
| `@nginx.log.directory@` | `nginx_log_directory` | Répertoire des logs |
| `@adr.api.rest.limit@` | `adr_api_rest_limit` | Limite API (ex: 20r/m) |
| `@adr.api.burst@` | `adr_api_burst` | Burst API |
| `@nginx.api.global.limit@` | `nginx_api_global_limit` | Limite globale |

---

## 📦 Scripts à Remplacer

### 1️⃣ `prepare-config.sh` + Ant + `build.xml`

**Fonction** : Filtre les tokens `@...@` dans les fichiers de configuration.

**Remplacement** :
- ✅ **Templates Jinja2** pour chaque fichier de configuration
- ✅ **Variables centralisées** dans `group_vars/all.yml`
- ✅ **Module `template` d'Ansible** pour le rendu

**Statut** : ✅ Solution validée (voir section "Solution Jinja2")

---

### 2️⃣ `1-nginx--setup.sh` (Script Principal d'Installation)

#### **Fonctionnalités**

| OS | Fonction | Détails |
|----|----------|---------|
| **Linux** | Installation NGINX | Configure repo officiel, installe via apt |
| **Linux** | Vérification version | Vérifie que version >= 1.30.2 |
| **Linux** | Création répertoires | Crée `tcpconf.d` |
| **Linux** | Copie configuration | Appelle `_copy_config.sh` |
| **Linux** | Copie static | Appelle `_copy_static.sh` |
| **Linux** | Certificats SSL | Appelle `_setup_certificate.sh` |
| **Linux** | Validation | `nginx -t && nginx -s reload` |
| **Windows** | Installation | Décompresse bundle NGINX |
| **Windows** | Copie configuration | Appelle les scripts |
| **Windows** | Service | Installe le service Windows |
| **Commun** | Permissions | `chmod -R 775 ./generated` |

#### **Variables Utilisées**

```bash
NGINX_linux_version='1.30.2+'
NGINX_win_version='nginx-1.30.2'
NGINX_win_file="resources/nginx/$NGINX_win_version.zip"
generatedproxysocks=generated/config/nginx/tcpconf.d/proxysocks.conf
destproxysocksfolder=tcpconf.d
```

#### **Logique Linux**

```bash
# 1. Vérifie si NGINX est installé
nginx -v > /dev/null 2>&1

# 2. Si non installé :
#    - Configure le repo NGINX officiel
#    - Installe via apt

# 3. Si installé mais version incorrecte :
#    - Affiche un warning et s'arrête

# 4. Crée les répertoires
mkdir -p $rootpath$destproxysocksfolder

# 5. Copie proxysocks.conf
cp $generatedproxysocks $rootpath$destproxysocksfolder/

# 6. Appelle les sous-scripts
chmod -R 775 ./generated
./generated/scripts/bash/_copy_config.sh
./generated/scripts/bash/_copy_static.sh
./generated/scripts/bash/_setup_certificate.sh

# 7. Validation et reload
nginx -t && nginx -s reload
```

#### **Solution Ansible**

```yaml
# roles/nginx/tasks/setup.yml

- name: Install NGINX (Ubuntu)
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: yes
  when:
    - ansible_facts['os_family'] == 'Debian'
    - ansible_facts['distribution'] == 'Ubuntu'
  tags: [nginx, install]

- name: Verify NGINX version
  ansible.builtin.command: nginx -v
  register: nginx_version
  changed_when: false
  check_mode: no

- name: Assert NGINX version is supported
  ansible.builtin.assert:
    that: nginx_version.stdout is regex('1\.(28|30)\.')
    msg: "NGINX version {{ nginx_version.stdout }} is not supported. Required: >= 1.30.2"
  tags: [nginx, install]

- name: Create tcpconf.d directory
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/tcpconf.d"
    state: directory
    mode: '0755'
    owner: root
    group: root
  tags: [nginx, config]

- name: Deploy proxysocks.conf
  ansible.builtin.template:
    src: config/nginx/tcpconf.d/proxysocks.conf.j2
    dest: "{{ nginx_home_directory }}/tcpconf.d/proxysocks.conf"
    mode: '0644'
    owner: root
    group: root
  tags: [nginx, config]

- name: Set permissions on generated files
  ansible.builtin.file:
    path: "{{ nginx_extract_path }}/generated"
    state: directory
    recurse: yes
    mode: '0775'
  tags: [nginx, config]

- name: Include config deployment tasks
  ansible.builtin.include_tasks: deploy_config.yml

- name: Include static files deployment tasks
  ansible.builtin.include_tasks: deploy_static.yml

- name: Include certificate setup tasks
  ansible.builtin.include_tasks: setup_certificate.yml

- name: Validate NGINX configuration
  ansible.builtin.command: nginx -t
  changed_when: false
  register: nginx_test
  tags: [nginx, validate]

- name: Reload NGINX
  ansible.builtin.service:
    name: nginx
    state: reloaded
  when: nginx_test.rc == 0
  tags: [nginx, reload]
```

---

### 3️⃣ `_copy_config.sh` (Copie des Fichiers de Configuration)

#### **Fonctionnalités**

- **Linux** : Demande confirmation pour chaque type de fichier via `select`
- **Windows** : Écrase tout par défaut
- Copie les fichiers depuis `generated/config/nginx/` vers :
  - `nginx.conf` → `/etc/nginx/nginx.conf`
  - `proxysocks.conf` → `/etc/nginx/tcpconf.d/proxysocks.conf`
  - `ampacimon.conf` → `/etc/nginx/sites-enabled/ampacimon.conf`
  - `apcm-shared/*` → `/etc/nginx/ampacimon-shared/`
  - `apcm-config/*` → `/etc/nginx/ampacimon-config/`

#### **Problèmes**

- **Interactif** : Nécessite input utilisateur (incompatible avec Ansible non-interactif)
- **Hardcodé** : Chemins et noms de fichiers en dur
- **Rigidité** : Pas adaptable à différents environnements

#### **Solution Ansible**

```yaml
# roles/nginx/tasks/deploy_config.yml

- name: Create NGINX config directories
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/{{ item }}"
    state: directory
    mode: '0755'
    owner: root
    group: root
  loop:
    - "{{ nginx_config_name }}-config"
    - "{{ nginx_config_name }}-shared"
    - sites-enabled
    - tcpconf.d
  tags: [nginx, config]

- name: Deploy nginx.conf
  ansible.builtin.template:
    src: config/nginx/conf/nginx.conf.j2
    dest: "{{ nginx_home_directory }}/conf/nginx.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
    backup: yes
  tags: [nginx, config]

- name: Deploy proxysocks.conf
  ansible.builtin.template:
    src: config/nginx/tcpconf.d/proxysocks.conf.j2
    dest: "{{ nginx_home_directory }}/tcpconf.d/proxysocks.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
    backup: yes
  tags: [nginx, config]

- name: Deploy main site configuration
  ansible.builtin.template:
    src: config/nginx/sites-enabled/ampacimon.conf.j2
    dest: "{{ nginx_home_directory }}/sites-enabled/{{ nginx_config_name }}.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
    backup: yes
  tags: [nginx, config]

- name: Deploy apcm-shared configurations
  ansible.builtin.template:
    src: "config/nginx/apcm-shared/{{ item }}.j2"
    dest: "{{ nginx_home_directory }}/{{ nginx_config_name }}-shared/{{ item }}"
    mode: '0644'
    owner: root
    group: root
  loop:
    - security-headers.shared
    - uptimerobot.shared
  tags: [nginx, config]

- name: Deploy apcm-config configurations
  ansible.builtin.template:
    src: "config/nginx/apcm-config/{{ item }}.j2"
    dest: "{{ nginx_home_directory }}/{{ nginx_config_name }}-config/{{ item }}"
    mode: '0644'
    owner: root
    group: root
  loop:
    - certificates.config
    - custom-rules.config
    - app-access.config
    - admin-access.config
    - api-access.config
  tags: [nginx, config]
```

---

### 4️⃣ `_copy_static.sh` (Copie des Fichiers Statiques)

#### **Fonctionnalités**

```bash
if [ "$OSTYPE" == "linux-gnu" ]; then
    staticdest='@static.files.folder@'
elif [ "$OSTYPE" == "msys" ]; then
    staticdest=$(cygpath '@static.files.folder@')
fi

mkdir -p $staticdest
if [ "$OSTYPE" == "linux-gnu" ]; then
  chown -R www-data:www-data $staticdest
fi
cp generated/static/* $staticdest
```

#### **Solution Ansible**

```yaml
# roles/nginx/tasks/deploy_static.yml

- name: Create static files directory
  ansible.builtin.file:
    path: "{{ static_files_folder }}"
    state: directory
    mode: '0755'
    owner: root
    group: root
  tags: [nginx, static]

- name: Deploy static files
  ansible.builtin.copy:
    src: "config/static/{{ item }}"
    dest: "{{ static_files_folder }}/{{ item }}"
    mode: '0644'
    owner: root
    group: root
  loop:
    - favicon.ico
    - index.html
    - error.html
    - SofiaPro-Medium.woff
  tags: [nginx, static]

- name: Set ownership on static files (Linux)
  ansible.builtin.file:
    path: "{{ static_files_folder }}"
    state: directory
    recurse: yes
    owner: www-data
    group: www-data
  when: ansible_facts['os_family'] != 'Windows'
  tags: [nginx, static]
```

---

### 5️⃣ `_setup_certificate.sh` (Configuration des Certificats SSL)

#### **Fonctionnalités**

| Fonction | Détails |
|----------|---------|
| **Self-signed (IP)** | `openssl req -x509 ... -config default-cert-ip.cnf` |
| **Self-signed (DNS)** | `openssl req -x509 ... -config default-cert-dns.cnf` |
| **Custom cert** | Copie les fichiers `.crt` et `.key` fournis |
| **ffdhe2048.txt** | Copie vers `@nginx.home.directory@/` |

**Variables** :
- `@ext.host.fqdn@` → Détermine IP ou DNS based
- `@nginx.home.directory@` → Destination des certificats

#### **Problèmes**

- **Interactif** : Demande à l'utilisateur ce qu'il veut faire
- **Hardcodé** : Chemins et noms de fichiers en dur
- **Pas automatisable** : Nécessite input manuel

#### **Solution Ansible**

**Option 1 : Certificats Auto-Signés (par défaut)**

```yaml
# roles/nginx/tasks/setup_certificate.yml

- name: Create certificates directory
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/certs"
    state: directory
    mode: '0755'
    owner: root
    group: root
  tags: [nginx, cert]

- name: Copy DH parameters
  ansible.builtin.copy:
    src: config/nginx/certs/ffdhe2048.txt
    dest: "{{ nginx_home_directory }}/ffdhe2048.txt"
    mode: '0644'
    owner: root
    group: root
  tags: [nginx, cert]

- name: Generate self-signed certificate (IP-based)
  community.crypto.openssl_certificate:
    path: "{{ nginx_home_directory }}/certs/apcm-cert.crt"
    privatekey_path: "{{ nginx_home_directory }}/certs/apcm-cert.key"
    csr_path: "{{ nginx_home_directory }}/certs/apcm-cert.csr"
    provider: selfsigned
    selfsigned_not_after: +3600d  # 10 ans
    selfsigned_digest: sha256
    selfsigned_version: 3
    selfsigned_key_usage:
      - digitalSignature
      - keyEncipherment
    selfsigned_extended_key_usage:
      - serverAuth
    selfsigned_subject:
      C: BE
      ST: "Liegge"
      L: "Loncin"
      O: "Ampacimon"
      OU: "IT"
      CN: "{{ nginx_config_name }}"
    selfsigned_ip:
      - "{{ ext_host_fqdn | ipaddr }}"
  when:
    - ext_host_fqdn | ipaddr
    - nginx_cert_type == 'selfsigned'
  tags: [nginx, cert]

- name: Generate self-signed certificate (DNS-based)
  community.crypto.openssl_certificate:
    path: "{{ nginx_home_directory }}/certs/apcm-cert.crt"
    privatekey_path: "{{ nginx_home_directory }}/certs/apcm-cert.key"
    csr_path: "{{ nginx_home_directory }}/certs/apcm-cert.csr"
    provider: selfsigned
    selfsigned_not_after: +3600d
    selfsigned_digest: sha256
    selfsigned_subject:
      C: BE
      ST: "Liegge"
      L: "Loncin"
      O: "Ampacimon"
      OU: "IT"
      CN: "{{ ext_host_fqdn }}"
    selfsigned_dns:
      - "{{ ext_host_fqdn }}"
  when:
    - not (ext_host_fqdn | ipaddr)
    - nginx_cert_type == 'selfsigned'
  tags: [nginx, cert]
```

**Option 2 : Certificats Custom (fournis par l'utilisateur)**

```yaml
- name: Deploy custom certificate (if provided)
  ansible.builtin.copy:
    src: "{{ nginx_ssl_cert_source }}"
    dest: "{{ nginx_home_directory }}/certs/apcm-cert.crt"
    mode: '0644'
    owner: root
    group: root
  when:
    - nginx_cert_type == 'custom'
    - nginx_ssl_cert_source is defined
  tags: [nginx, cert]

- name: Deploy custom key (if provided)
  ansible.builtin.copy:
    src: "{{ nginx_ssl_key_source }}"
    dest: "{{ nginx_home_directory }}/certs/apcm-cert.key"
    mode: '0600'
    owner: root
    group: root
  when:
    - nginx_cert_type == 'custom'
    - nginx_ssl_key_source is defined
  tags: [nginx, cert]
```

**Variables à définir** :

```yaml
# group_vars/all.yml
nginx_cert_type: "selfsigned"  # selfsigned, custom, or existing
nginx_ssl_cert_source: ""     # Chemin vers le certificat custom
nginx_ssl_key_source: ""      # Chemin vers la clé custom
```

---

### 6️⃣ `2-nginx--deploy-cron.sh` (Déploiement des Tâches Cron)

#### **Fonctionnalités**

- **Linux** : Appelle `_create-cronjob.sh`
- **Windows** : Appelle `_create-schtask.ps1` via PowerShell admin

#### **Solution Ansible**

```yaml
# roles/nginx/tasks/deploy_cron.yml

- name: Include Linux cron tasks
  ansible.builtin.include_tasks: deploy_cron_linux.yml
  when: ansible_facts['os_family'] != 'Windows'
  tags: [nginx, cron]

- name: Include Windows scheduled task
  ansible.builtin.include_tasks: deploy_cron_windows.yml
  when: ansible_facts['os_family'] == 'Windows'
  tags: [nginx, cron]
```

---

### 7️⃣ `_create-cronjob.sh` (Création de la Tâche Cron Linux)

#### **Fonctionnalités**

1. Crée l'utilisateur `Scriptuser` si inexistant
2. Ajoute `Scriptuser` aux groupes `root` et `adm`
3. Vérifie que `Scriptuser` peut lire les logs NGINX
4. Crée les répertoires :
   - `/apcm-maintenance/`
   - `/apcm-maintenance/data/`
   - `/apcm-maintenance/bin/`
5. Copie les fichiers :
   - `generated/conf/apcm-maintenance/maintenance.ini` → `/apcm-maintenance/data/maintenance.ini`
   - `generated/conf/apcm-maintenance/exportNGINX.ini` → `/apcm-maintenance/data/exportNGINX.ini`
   - `generated/scripts/bash/cron/exportNGINXLogs.sh` → `/apcm-maintenance/exportNGINXLogs.sh`
6. Ajoute `logdir=@nginx.log.directory@` à `exportNGINX.ini`
7. Configure les permissions
8. Crée l'entrée cron : `10 0 * * * cd /apcm-maintenance && /apcm-maintenance/exportNGINXLogs.sh`

#### **Variables** :

- `service="Scriptuser"`
- `logdir="@nginx.log.directory@"`

#### **Solution Ansible**

```yaml
# roles/nginx/tasks/deploy_cron_linux.yml

- name: Create maintenance user
  ansible.builtin.user:
    name: Scriptuser
    state: present
    system: yes
    shell: /bin/bash
    home: /home/Scriptuser
    create_home: yes
  tags: [nginx, cron]

- name: Add Scriptuser to root group
  ansible.builtin.user:
    name: Scriptuser
    groups: root
    append: yes
  tags: [nginx, cron]

- name: Add Scriptuser to adm group
  ansible.builtin.user:
    name: Scriptuser
    groups: adm
    append: yes
  tags: [nginx, cron]

- name: Create maintenance directories
  ansible.builtin.file:
    path: "/apcm-maintenance/{{ item }}"
    state: directory
    mode: '0755'
    owner: Scriptuser
    group: Scriptuser
  loop:
    - ""
    - data
    - bin
  tags: [nginx, cron]

- name: Deploy maintenance.ini
  ansible.builtin.copy:
    src: conf/apcm-maintenance/maintenance.ini
    dest: /apcm-maintenance/data/maintenance.ini
    mode: '0600'
    owner: Scriptuser
    group: Scriptuser
  tags: [nginx, cron]

- name: Deploy exportNGINX.ini
  ansible.builtin.template:
    src: conf/apcm-maintenance/exportNGINX.ini.j2
    dest: /apcm-maintenance/data/exportNGINX.ini
    mode: '0600'
    owner: Scriptuser
    group: Scriptuser
  tags: [nginx, cron]

- name: Deploy exportNGINXLogs.sh
  ansible.builtin.copy:
    src: scripts/bash/cron/exportNGINXLogs.sh
    dest: /apcm-maintenance/exportNGINXLogs.sh
    mode: '0700'
    owner: Scriptuser
    group: Scriptuser
  tags: [nginx, cron]

- name: Ensure Scriptuser can read NGINX logs
  ansible.builtin.file:
    path: "{{ nginx_log_directory }}"
    state: directory
    recurse: yes
    mode: '0750'
    owner: root
    group: adm
  tags: [nginx, cron]

- name: Add cron job for NGINX log export
  ansible.builtin.cron:
    name: "Export NGINX logs"
    user: Scriptuser
    job: "cd /apcm-maintenance && /apcm-maintenance/exportNGINXLogs.sh"
    minute: "10"
    hour: "0"
    state: present
  tags: [nginx, cron]
```

**Template pour exportNGINX.ini.j2** :

```jinja2
[DEFAULT]
destination={{ nginx_log_export_destination | default('/mnt/backup') }}

[NGINX]
logdir={{ nginx_log_directory }}
```

---

## 🎯 Solution Globale Recommandée

### **Architecture Cible**

```
roles/nginx/
├── defaults/
│   └── main.yml          # Variables par défaut
├── files/
│   ├── ffdhe2048.txt      # Fichiers statiques
│   └── scripts/          # Scripts à copier (exportNGINXLogs.sh, etc.)
├── templates/
│   ├── config/           # Templates Jinja2
│   │   ├── nginx/
│   │   │   ├── conf/
│   │   │   │   └── nginx.conf.j2
│   │   │   ├── sites-enabled/
│   │   │   │   └── ampacimon.conf.j2
│   │   │   ├── apcm-config/
│   │   │   │   ├── certificates.config.j2
│   │   │   │   ├── custom-rules.config.j2
│   │   │   │   └── ...
│   │   │   └── apcm-shared/
│   │   │       ├── security-headers.shared.j2
│   │   │       └── uptimerobot.shared.j2
│   │   └── static/       # Fichiers statiques à copier
│   │       ├── favicon.ico
│   │       └── ...
│   └── conf/
│       └── apcm-maintenance/
│           └── exportNGINX.ini.j2
└── tasks/
    ├── main.yml           # Point d'entrée
    ├── setup.yml          # Installation NGINX
    ├── generate_config.yml # Génération configs (remplace prepare-config.sh)
    ├── deploy_config.yml   # Déploiement configs (remplace _copy_config.sh)
    ├── deploy_static.yml   # Déploiement static (remplace _copy_static.sh)
    ├── setup_certificate.yml # Certificats (remplace _setup_certificate.sh)
    ├── deploy_cron.yml      # Tâches cron (remplace 2-nginx--deploy-cron.sh)
    ├── deploy_cron_linux.yml
    └── deploy_cron_windows.yml
```

### **Variables à Définir**

```yaml
# group_vars/all.yml

# ============================================================
# NGINX - Base Configuration
# ============================================================
nginx_config_name: "ampacimon"
nginx_home_directory: "/etc/nginx"
nginx_log_directory: "/var/log/nginx"
static_files_folder: "/var/www/{{ nginx_config_name }}"

# ============================================================
# NGINX - Network Configuration
# ============================================================
keycloak_host_fqdn: "auth.{{ domain }}"
keycloak_https_port: 8543
keycloak_management_port: 9000

adr_server_host_fqdn: "api.{{ domain }}"
adr_server_https_port: 8181

adr_front_host_fqdn: "{{ domain }}"
adr_front_https_port: 8181

facility_front_host_fqdn: "{{ domain }}"
facility_front_https_port: 4949

ext_host_fqdn: "{{ domain }}"

# ============================================================
# NGINX - API Configuration
# ============================================================
adr_api_rest_limit: "20r/m"
adr_api_burst: 20
nginx_api_global_limit: "100r/s"

# ============================================================
# NGINX - Security Configuration
# ============================================================
nginx_unknown_ip_behavior: "deny all;"
nginx_mui_access: "admin"
keycloak_publish_wellknown: false
nginx_root_path: "/index.html"

# ============================================================
# NGINX - Data Configuration
# ============================================================
nginx_datadir: "/opt/adr/data"
nginx_datadir_user: ""
nginx_datadir_password: ""

# ============================================================
# NGINX - SSL Configuration
# ============================================================
nginx_cert_type: "selfsigned"  # selfsigned, custom, existing
nginx_ssl_cert_source: ""    # Chemin vers certificat custom
nginx_ssl_key_source: ""     # Chemin vers clé custom
nginx_ssl_cert_path: "{{ nginx_home_directory }}/certs/apcm-cert.crt"
nginx_ssl_key_path: "{{ nginx_home_directory }}/certs/apcm-cert.key"

# ============================================================
# NGINX - Cron Configuration
# ============================================================
nginx_log_export_destination: "/mnt/backup"
```

---

## 🚀 Plan de Migration

### **Phase 1 : Préparation (1 jour)**
- [ ] Créer la structure `roles/nginx/templates/`
- [ ] Convertir 2-3 fichiers de config en templates Jinja2
- [ ] Définir les variables dans `group_vars/all.yml`
- [ ] Tester le templating en local

### **Phase 2 : Migration NGINX (2-3 jours)**
- [ ] Convertir tous les fichiers de config NGINX en templates
- [ ] Créer les tâches Ansible pour chaque script :
  - [ ] `setup.yml` (remplace `1-nginx--setup.sh`)
  - [ ] `deploy_config.yml` (remplace `_copy_config.sh`)
  - [ ] `deploy_static.yml` (remplace `_copy_static.sh`)
  - [ ] `setup_certificate.yml` (remplace `_setup_certificate.sh`)
  - [ ] `deploy_cron.yml` (remplace `2-nginx--deploy-cron.sh` et `_create-cronjob.sh`)
- [ ] Intégrer dans le rôle existant
- [ ] Tester en environnement de dev

### **Phase 3 : Validation (1 jour)**
- [ ] Tester le déploiement complet
- [ ] Vérifier que toutes les fonctionnalités sont présentes
- [ ] Corriger les éventuels problèmes

### **Phase 4 : Nettoyage (1/2 jour)**
- [ ] Supprimer `TMP-CONFIG/`
- [ ] Supprimer les références aux scripts dans le code
- [ ] Mettre à jour la documentation
- [ ] Commit et merge

---

## 📌 Points d'Attention

### **1. Dépendances Ansible**
- **`community.crypto`** : Pour la génération des certificats auto-signés
  ```bash
  ansible-galaxy collection install community.crypto
  ```

### **2. Compatibilité Windows**
- Les tâches Linux doivent être conditionnées :
  ```yaml
  when: ansible_facts['os_family'] != 'Windows'
  ```
- Les tâches Windows doivent être conditionnées :
  ```yaml
  when: ansible_facts['os_family'] == 'Windows'
  ```

### **3. Variables par Environnement**
- Créer des fichiers spécifiques :
  ```
group_vars/
├── dev/
│   └── nginx.yml
├── staging/
│   └── nginx.yml
└── prod/
    └── nginx.yml
  ```

### **4. Secrets**
- Les mots de passe et clés doivent être dans `group_vars/all_secrets.yml` encodé avec Ansible Vault :
  ```bash
  ansible-vault encrypt group_vars/all_secrets.yml
  ```

---

## 🎉 Bénéfices Attendus

| **Critère** | **Avant** | **Après** |
|------------|-----------|-----------|
| **Complexité** | ❌ Scripts shell + Ant + interactions utilisateur | ✅ Ansible natif |
| **Maintenabilité** | ❌ Fichiers statiques, scripts non versionnés | ✅ Tout versionné dans Git |
| **Automatisation** | ❌ Requiert input manuel | ✅ 100% automatique |
| **Reproductibilité** | ❌ Dépend des bundles externes | ✅ Déterministe |
| **Flexibilité** | ❌ Hardcodé | ✅ Adaptable par environnement |
| **Validation** | ❌ Manuelle | ✅ Automatique (`nginx -t`) |
| **Idempotence** | ❌ Pas garanti | ✅ Garanti par Ansible |
| **Documentation** | ❌ Dans les scripts | ✅ Centralisée |

---

## 🔧 Analyse Détaillée des Scripts `1-nginx--setup.sh` et `2-nginx--deploy-cron.sh`

### 📄 `1-nginx--setup.sh` - Script Principal d'Installation et Configuration

**Localisation** : `TMP-CONFIG/sources/nginx/apcm-nginx-bundle-4.0.11-nginx-bundle/apcm-nginx-bundle/1-nginx--setup.sh`

#### **Fonctionnalités par OS**

##### **🐧 Linux**

**1. Installation de NGINX**
```bash
# Vérifie si NGINX est installé
nginx -v > /dev/null 2>&1

# Si non installé :
# - Détecte Ubuntu via /etc/*release
# - Configure le repo NGINX officiel avec clé GPG
# - Vérifie les fingerprints des clés
# - Ajoute le repo : deb [signed-by=...] http://nginx.org/packages/ubuntu `lsb_release -cs` nginx
# - Installe via : apt satisfy "nginx (>=1.30.2)" -y

# Si installé mais version incorrecte :
# - Affiche warning et s'arrête
```

**Variables Linux** :
```bash
NGINX_linux_version='1.30.2+'
rootpath=/etc/nginx/
destproxysocksfolder=tcpconf.d
generatedproxysocks=generated/config/nginx/tcpconf.d/proxysocks.conf
```

**2. Configuration**
```bash
# Crée répertoire tcpconf.d
mkdir -p $rootpath$destproxysocksfolder

# Copie proxysocks.conf
cp $generatedproxysocks $rootpath$destproxysocksfolder/

# Permissions
chmod -R 775 ./generated

# Appelle les sous-scripts
./generated/scripts/bash/_copy_config.sh
./generated/scripts/bash/_copy_static.sh
./generated/scripts/bash/_setup_certificate.sh
```

**3. Validation et Reload**
```bash
nginx -t && nginx -s reload || echo "[ERREUR] Configuration invalide"
```

##### **🪟 Windows**

**1. Désinstallation du service existant**
```bash
./generated/service/uninstall.sh
```

**2. Déploiement**
```bash
# Nettoyage
rm -rf nginx

# Décompression du bundle
unzip $NGINX_win_file
mv $NGINX_win_version nginx

rootpath=nginx/
```

**3. Configuration (même que Linux)**
```bash
mkdir -p $rootpath$destproxysocksfolder
cp $generatedproxysocks $rootpath$destproxysocksfolder/
chmod -R 775 ./generated
./generated/scripts/bash/_copy_config.sh
./generated/scripts/bash/_copy_static.sh
./generated/scripts/bash/_setup_certificate.sh
```

**4. Validation**
```bash
cd nginx
./nginx.exe -t
cd ..
```

**5. Installation du Service**
```bash
./generated/service/install.sh
```

**Variables Windows** :
```bash
NGINX_win_version='nginx-1.30.2'
NGINX_win_file="resources/nginx/$NGINX_win_version.zip"
```

#### **Problèmes Identifiés**

| Problème | Impact | Solution Ansible |
|----------|--------|------------------|
| **Interactivité** | Bloque l'automatisation | Utiliser des variables par défaut |
| **Hardcoded paths** | Pas flexible | Variables Ansible |
| **Vérification fingerprint** | Complexe | Module `apt_key` ou `get_url` |
| **Version checking** | Parsing manuel | Module `command` + regex |
| **Service management** | Spécifique OS | Modules `service` et `win_service` |

#### **Solution Ansible Complète**

```yaml
# roles/nginx/tasks/setup_nginx.yml

# ============================================================
# 1. Installation NGINX
# ============================================================

- name: Install NGINX on Ubuntu
  block:
    - name: Add NGINX GPG key
      ansible.builtin.get_url:
        url: https://nginx.org/keys/nginx_signing.key
        dest: /tmp/nginx_signing.key
        mode: '0644'
      register: gpg_key
      until: gpg_key is succeeded
      retries: 3
      delay: 5

    - name: Convert GPG key to keyring format
      ansible.builtin.command: >
        gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg /tmp/nginx_signing.key
      args:
        creates: /usr/share/keyrings/nginx-archive-keyring.gpg

    - name: Verify GPG key fingerprints
      ansible.builtin.command: >
        gpg --dry-run --quiet --no-keyring --import --import-options import-show
        /usr/share/keyrings/nginx-archive-keyring.gpg | sed -nr 's/^([ ]+)([0-9A-Z]{40}$)/\2/p'
      register: key_fingerprints
      changed_when: false

    - name: Assert GPG key fingerprints are valid
      ansible.builtin.assert:
        that:
          - "'8540A6F18833A80E9C1653A42FD21310B49F6B46' in key_fingerprints.stdout"
          - "'573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62' in key_fingerprints.stdout"
          - "'9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3' in key_fingerprints.stdout"
        msg: "NGINX GPG key fingerprints are invalid"

    - name: Add NGINX repository
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu {{ ansible_distribution_release }} nginx"
        state: present
        filename: nginx

    - name: Set NGINX repo priority
      ansible.builtin.copy:
        dest: /etc/apt/preferences.d/99nginx
        content: |
          Package: *
          Pin: origin nginx.org
          Pin: release o=nginx
          Pin-Priority: 900
        mode: '0644'

    - name: Install NGINX
      ansible.builtin.apt:
        name: "nginx>=1.30.2"
        state: present
        update_cache: yes
        cache_valid_time: 3600

  when:
    - ansible_facts['os_family'] == 'Debian'
    - ansible_facts['distribution'] == 'Ubuntu'
  tags: [nginx, install, linux]

- name: Install NGINX on other Debian distributions
  ansible.builtin.apt:
    name: "nginx>=1.30.2"
    state: present
    update_cache: yes
  when:
    - ansible_facts['os_family'] == 'Debian'
    - ansible_facts['distribution'] != 'Ubuntu'
  tags: [nginx, install, linux]

- name: Install NGINX on RedHat
  ansible.builtin.yum:
    name: nginx
    state: present
  when: ansible_facts['os_family'] == 'RedHat'
  tags: [nginx, install, linux]

# ============================================================
# 2. Vérification de la Version
# ============================================================

- name: Check NGINX version
  ansible.builtin.command: nginx -v
  register: nginx_version_result
  changed_when: false
  check_mode: no
  tags: [nginx, verify]

- name: Assert NGINX version is supported
  ansible.builtin.assert:
    that: nginx_version_result.stdout is regex('nginx version: nginx/1\.(28|29|30)\.')
    msg: >
      NGINX version {{ nginx_version_result.stdout }} is not supported.
      Required: >= 1.30.2
      To fix: apt install --only-upgrade nginx
  tags: [nginx, verify]

# ============================================================
# 3. Windows - Extraction du Bundle
# ============================================================

- name: Extract NGINX bundle on Windows
  community.windows.win_unzip:
    src: "{{ nginx_extract_path }}/apcm-nginx-bundle/resources/nginx/{{ nginx_win_bundle }}"
    dest: "{{ nginx_install_path }}"
    creates: "{{ nginx_install_path }}/nginx/nginx.exe"
  when: ansible_facts['os_family'] == 'Windows'
  tags: [nginx, install, windows]

# ============================================================
# 4. Création des Répertoires
# ============================================================

- name: Create tcpconf.d directory
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/tcpconf.d"
    state: directory
    mode: '0755'
    owner: root
    group: root
  tags: [nginx, config]

# ============================================================
# 5. Déploiement de proxysocks.conf
# ============================================================

- name: Deploy proxysocks.conf
  ansible.builtin.template:
    src: config/nginx/tcpconf.d/proxysocks.conf.j2
    dest: "{{ nginx_home_directory }}/tcpconf.d/proxysocks.conf"
    mode: '0644'
    owner: root
    group: root
  tags: [nginx, config]

# ============================================================
# 6. Appel des Sous-Scripts (remplacés par Ansible)
# ============================================================

- name: Set permissions on generated files
  ansible.builtin.file:
    path: "{{ nginx_extract_path }}/generated"
    state: directory
    recurse: yes
    mode: '0775'
  tags: [nginx, config]

- name: Include config deployment
  ansible.builtin.include_tasks: deploy_config.yml
  tags: [nginx, config]

- name: Include static files deployment
  ansible.builtin.include_tasks: deploy_static.yml
  tags: [nginx, static]

- name: Include certificate setup
  ansible.builtin.include_tasks: setup_certificate.yml
  tags: [nginx, cert]

# ============================================================
# 7. Validation et Reload
# ============================================================

- name: Validate NGINX configuration
  ansible.builtin.command: nginx -t
  register: nginx_test
  changed_when: false
  tags: [nginx, validate]

- name: Reload NGINX service
  ansible.builtin.service:
    name: nginx
    state: reloaded
  when:
    - nginx_test.rc == 0
    - ansible_facts['os_family'] != 'Windows'
  tags: [nginx, reload]

- name: Validate NGINX configuration (Windows)
  ansible.windows.win_command: .\nginx.exe -t
  args:
    chdir: "{{ nginx_install_path }}/nginx"
  when: ansible_facts['os_family'] == 'Windows'
  tags: [nginx, validate, windows]

# ============================================================
# 8. Installation du Service Windows
# ============================================================

- name: Install NGINX as Windows service
  ansible.windows.win_command: .\service\install.sh
  args:
    chdir: "{{ nginx_install_path }}"
    creates: "{{ nginx_install_path }}\nginx\nginx.exe"
  when: ansible_facts['os_family'] == 'Windows'
  tags: [nginx, service, windows]

# ============================================================
# Variables Requises
# ============================================================
#
# nginx_extract_path: /opt/adr/apcm-nginx-bundle-4.0.11
# nginx_install_path: /etc/nginx (Linux) ou C:\adr\nginx (Windows)
# nginx_home_directory: /etc/nginx
# nginx_win_bundle: nginx-1.30.2.zip

```

---

### 📄 `2-nginx--deploy-cron.sh` - Déploiement des Tâches Planifiées

**Localisation** : `TMP-CONFIG/sources/nginx/apcm-nginx-bundle-4.0.11-nginx-bundle/apcm-nginx-bundle/2-nginx--deploy-cron.sh`

#### **Code Source**
```bash
#!/bin/bash
# Shell script for redeploying crontab.
# Version: 4.0.11

echo
if [ "$OSTYPE" == "linux-gnu" ]; then 
    echo "Deploying cron tab"
    ./generated/scripts/bash/_create-cronjob.sh
elif [ "$OSTYPE" == "msys" ]; then
    echo "Deploying Scheduled task"
    currentdir=$(pwd)
    schtaskscript=$(cygpath -w "${currentdir}/generated/scripts/posh/_create-schtask.ps1")
    powershell.exe -executionpolicy bypass -Command "Start-Process -FilePath powershell.exe -ArgumentList \"-executionpolicy bypass -File \"\"${schtaskscript}\"\"\" -verb runas -wait"
fi
echo
```

#### **Fonctionnalités**

| OS | Action | Script Appelé |
|----|--------|----------------|
| **Linux** | Déploie cron | `_create-cronjob.sh` |
| **Windows** | Déploie Scheduled Task | `_create-schtask.ps1` (via PowerShell admin) |

#### **Problèmes**

| Problème | Impact | Solution Ansible |
|----------|--------|------------------|
| **Interactivité Windows** | Requiert UAC | Utiliser module `win_scheduled_task` |
| **Chemins hardcodés** | Pas flexible | Variables Ansible |
| **Dépendance à cygpath** | Spécifique | Géré par modules Windows |

---

### 📄 `_create-cronjob.sh` - Création de la Tâche Cron (Linux)

**Localisation** : `TMP-CONFIG/sources/nginx/apcm-nginx-bundle-4.0.11-nginx-bundle/apcm-nginx-bundle/resources/scripts/bash/_create-cronjob.sh`

#### **Fonctionnalités Détaillées**

**1. Initialisation**
```bash
service="Scriptuser"
scriptdest="$parrentdir/apcm-maintenance"
datadest="$scriptdest/data"
bindest="$scriptdest/bin"
mkdir -p $scriptdest
mkdir -p $datadest
mkdir -p $bindest
```

**2. Gestion de l'Utilisateur**
```bash
# Crée l'utilisateur si inexistant
if id -u "$service" >/dev/null 2>&1; then
    echo "User $service exists."
else
    echo "User $service does not exist. Creating..."
    useradd -m "$service"
fi

# Ajoute aux groupes root et adm
gpasswd --add Scriptuser root
gpasswd --add Scriptuser adm
```

**3. Vérification des Permissions**
```bash
# Vérifie que Scriptuser peut lire les logs
for logfile in $(find "$logdir" -maxdepth 1 -type f)
do
    sudo -u $service test -r $logfile
    if [ "$?" -gt 0 ]; then
        chmod -R 750 ${$logdir}
    fi
done
```

**4. Copie des Fichiers**
```bash
Maintenanceconfg="generated/conf/apcm-maintenance/maintenance.ini"
Maintenanceconfgd="$datadest/maintenance.ini"
nginxconfg="generated/conf/apcm-maintenance/exportNGINX.ini"
nginxconfgd="$datadest/exportNGINX.ini"
LogsS="generated/scripts/bash/cron/exportNGINXLogs.sh"
LogsSd="$scriptdest/exportNGINXLogs.sh"

cp "$Maintenanceconfg" "$Maintenanceconfgd"
cp "$nginxconfg" "$nginxconfgd"
cp "$LogsS" "$LogsSd"

# Ajoute logdir au fichier exportNGINX.ini
logdirconfg="logdir=\"${logdir}\""
echo $logdirconfg >> $nginxconfgd
```

**5. Configuration des Permissions**
```bash
chown "$service":"$service" "$scriptdest"
chown "$service":"$service" "$Maintenanceconfgd"
chown "$service":"$service" "$nginxconfgd"
chown "$service":"$service" "$LogsSd"

chmod 700 "$scriptdest"
chmod 600 "$Maintenanceconfgd"
chmod 600 "$nginxconfgd"
chmod 700 "$LogsSd"
```

**6. Création de la Tâche Cron**
```bash
cron_entry1="10 0 * * * cd $scriptdest && $LogsSd"
(crontab -l -u "$service" 2>/dev/null | grep -q -F -- "$cron_entry1") || 
  (crontab -l -u "$service" ; echo "$cron_entry1") | crontab -u "$service" -
```

#### **Variables Utilisées**

```bash
service="Scriptuser"
logdir="@nginx.log.directory@"  # Remplacé par Ansible
parrentdir=$(dirname "$(pwd)")
```

#### **Fichiers Utilisés**

- `generated/conf/apcm-maintenance/maintenance.ini` (template avec tokens)
- `generated/conf/apcm-maintenance/exportNGINX.ini` (template avec tokens)
- `generated/scripts/bash/cron/exportNGINXLogs.sh`

#### **Problèmes**

| Problème | Impact | Solution Ansible |
|----------|--------|------------------|
| **Hardcoded user** | Toujours Scriptuser | Variable Ansible |
| **Hardcoded paths** | /apcm-maintenance | Variable Ansible |
| **Interactif** | chmod automatique | Géré par Ansible |
| **Concaténation ini** | logdir ajouté manuellement | Template complet |

#### **Solution Ansible**

Voir la section dédiée dans le document principal.

---

### 📄 `_create-schtask.ps1` - Création des Tâches Planifiées (Windows)

**Localisation** : `TMP-CONFIG/sources/nginx/apcm-nginx-bundle-4.0.11-nginx-bundle/apcm-nginx-bundle/resources/scripts/posh/_create-schtask.ps1`

#### **Fonctionnalités Principales**

**1. Initialisation et Lecture des INI**
```powershell
# Lit maintenance.ini et exportNGINX.ini
$Maintenanceconfg="$Bundlepath\generated\conf\apcm-maintenance\maintenance.ini"
$nginxconfg="$Bundlepath\generated\conf\apcm-maintenance\exportNGINX.ini"

# Parse les fichiers INI
$maintenancedata = @{}
# ... parsing logic ...
```

**2. Définition des Variables**
```powershell
$service="Scriptuser"
$scriptdest="$parrentdir\apcm-maintenance"
$datadest="$scriptdest\data"
$logdir="@nginx.log.directory@"  # Remplacé par Ansible
```

**3. Montage des Partages Réseau**
```powershell
# Si destination est un partage réseau, le monte
if($maintenancedata.destination -match '\\\\.*'){
    if($maintenancedata.user -and $maintenancedata.password){
        New-SmbMapping -RemotePath $maintenancedata.destination 
          -UserName $maintenancedata.user -Password $maintenancedata.password
    } else {
        New-SmbMapping -RemotePath $maintenancedata.destination
    }
}
```

**4. Gestion du Compte de Service**
```powershell
# Crée le compte Scriptuser avec mot de passe aléatoire
$randompassword = ... # Génération aléatoire

if((Get-LocalUser -Name $service 2>$null)){
    # Utilisateur existe déjà
} else {
    net user $service $randompassword /ADD
    Set-LocalUser $service -PasswordNeverExpires $True
    Add-LocalGroupMember -group Administrators -Member $service
}
```

**5. Création des Tâches Planifiées**

**a. Tâche à la demande (On-Demand)**
```powershell
# Crée une tâche déclenchée par un événement Application
$trigger = New-CimInstance -ClassName MSFT_TaskEventTrigger
$trigger.Enabled = $true
$trigger.Subscription = '<QueryList><Query Id="0" Path="Application"><Select Path="Application">*[System[Provider[@Name=''ADR''] and EventID=100]]</Select></Query></QueryList>'

Register-ScheduledTask -TaskName "apcm-maintenance" 
  -Action $action -Trigger $trigger 
  -User $service -Password $randompassword
```

**b. Tâche de rotation des logs**
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" 
  -Argument "-noprofile -executionpolicy bypass -file \"$LogrotateSd\""
$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 1 -At 00:00

Register-ScheduledTask -TaskName "apcm-maintenance-rotatenginxLogs" 
  -Action $action -Trigger $trigger -User "System"
```

**c. Tâche d'export des logs** (via CSV)
```powershell
# Crée un fichier CSV avec les tâches à créer
$csvexportpath="$scriptdest\data\scheduledtasks.csv"
Write-Output "TaskName;TaskAction;TaskArguments" | Out-File $csvexportpath
Write-Output "apcm-maintenance-exportnginxLogs;powershell.exe;-noprofile -executionpolicy bypass -file \"$LogsSd\"" | 
  Out-File $csvexportpath -Append
```

**6. Déclenchement de la Tâche On-Demand**
```powershell
# Écrit dans l'EventLog pour déclencher la tâche
New-EventLog -LogName "Application" -Source "ADR" -ErrorAction silentlycontinue
Write-EventLog -LogName "Application" -Source "ADR" -EventID 100 
  -EntryType Information -Message "APCM-Maintenance completed."
```

#### **Variables des Fichiers INI**

**maintenance.ini** (avec tokens) :
```ini
[path]
destination="@nginx.datadir@"
user="@nginx.datadir.user@"
password="@nginx.datadir.password@"
```

**exportNGINX.ini** (avec tokens) :
```ini
[path]
logdir="@nginx.log.directory@"
```

#### **Problèmes**

| Problème | Impact | Solution Ansible |
|----------|--------|------------------|
| **Complexité** | Script PowerShell très long | Modules Ansible dédiés |
| **Hardcoded user** | Toujours Scriptuser | Variable Ansible |
| **Hardcoded paths** | Chemin absolu | Variables Ansible |
| **Génération aléatoire** | Mot de passe random | Variable Ansible ou Vault |
| **Montage réseau** | Spécifique Windows | Module `win_smb_mapping` |
| **EventLog** | Déclenchement manuel | Module `win_eventlog` |

#### **Solution Ansible**

```yaml
# roles/nginx/tasks/deploy_cron_windows.yml

- name: Create maintenance directories
  ansible.windows.win_file:
    path: "{{ win_maintenance_path }}\{{ item }}"
    state: directory
  loop:
    - ""
    - data
    - bin
    - data\protected

- name: Create maintenance user
  ansible.windows.win_user:
    name: "{{ win_maintenance_user | default('Scriptuser') }}"
    password: "{{ win_maintenance_password | default(lookup('passwordstore', 'generate_password')) }}"
    state: present
    password_never_expires: yes
    groups:
      - Administrators

- name: Mount network share (if needed)
  community.windows.win_smb_mapping:
    remote_path: "{{ nginx_datadir }}"
    local_path: "Z:"
    username: "{{ nginx_datadir_user | default(omit) }}"
    password: "{{ nginx_datadir_password | default(omit) }}"
    state: mapped
  when:
    - nginx_datadir.startswith('\\')
    - nginx_datadir_user != ''

- name: Deploy maintenance.ini
  ansible.windows.win_template:
    src: conf/apcm-maintenance/maintenance.ini.j2
    dest: "{{ win_maintenance_path }}\data\maintenance.ini"

- name: Deploy exportNGINX.ini
  ansible.windows.win_template:
    src: conf/apcm-maintenance/exportNGINX.ini.j2
    dest: "{{ win_maintenance_path }}\data\exportNGINX.ini"

- name: Deploy scripts
  ansible.windows.win_copy:
    src: "scripts/posh/{{ item }}"
    dest: "{{ win_maintenance_path }}\{{ item }}"
    mode: '0700'
  loop:
    - exportNGINXLogs.ps1
    - rotateNGINXLogs.ps1
    - onDemandTask.ps1

- name: Create scheduled task for log rotation
  ansible.windows.win_scheduled_task:
    name: apcm-maintenance-rotatenginxLogs
    description: "Rotate NGINX logs daily"
    actions:
      - path: powershell.exe
        arguments: "-noprofile -executionpolicy bypass -file \"{{ win_maintenance_path }}\rotateNGINXLogs.ps1\""
    triggers:
      - type: daily
        start_time: "00:00"
        enabled: yes
    user: SYSTEM
    state: present

- name: Create on-demand scheduled task
  ansible.windows.win_scheduled_task:
    name: apcm-maintenance
    description: "On-demand maintenance task"
    actions:
      - path: powershell.exe
        arguments: "-noprofile -executionpolicy bypass -file \"{{ win_maintenance_path }}\onDemandTask.ps1\""
    triggers:
      - type: event
        log: Application
        source: ADR
        event_id: 100
        enabled: yes
    user: "{{ win_maintenance_user | default('Scriptuser') }}"
    password: "{{ win_maintenance_password | default(lookup('passwordstore', 'generate_password')) }}"
    state: present

- name: Ensure EventLog source exists
  ansible.windows.win_eventlog:
    name: Application
    source: ADR
    state: present
```

---

## 📚 Références

- [Ansible Template Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible File Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Ansible Cron Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/cron_module.html)
- [Ansible User Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/user_module.html)
- [Community Crypto Collection](https://docs.ansible.com/ansible/latest/collections/community/crypto/index.html)
- [OpenSSL Certificate Module](https://docs.ansible.com/ansible/latest/collections/community/crypto/openssl_certificate_module.html)
