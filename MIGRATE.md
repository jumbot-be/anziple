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

## 🎯 Solutions Complètes par Script

### 🔹 Remplacement de `1-nginx--setup.sh`

**Fichier Ansible** : `roles/nginx/tasks/setup_nginx.yml`

```yaml
---
# roles/nginx/tasks/setup_nginx.yml

# ============================================================
# Étape 1 : Installation NGINX (selon l'OS)
# ============================================================

- name: Include OS-specific installation tasks
  ansible.builtin.include_tasks: "install_{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [nginx, install]

# ============================================================
# Étape 2 : Vérification de la version
# ============================================================

- name: Check NGINX version
  ansible.builtin.command: nginx -v
  register: nginx_version_result
  changed_when: false
  check_mode: no
  ignore_errors: yes
  tags: [nginx, verify]

- name: Assert NGINX version is supported
  ansible.builtin.assert:
    that: nginx_version_result.stdout is regex('nginx version: nginx/1\.(28|29|30)\.')
    msg: >
      NGINX version {{ nginx_version_result.stdout | default('not found') }} is not supported.
      Required: >= 1.30.2
      On Ubuntu: sudo apt install --only-upgrade nginx
      On Windows: Replace bundle with version 1.30.2+
  tags: [nginx, verify]

# ============================================================
# Étape 3 : Création des répertoires
# ============================================================

- name: Create NGINX directory structure
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/{{ item }}"
    state: directory
    mode: '0755'
    owner: root
    group: root
  loop:
    - "tcpconf.d"
    - "{{ nginx_config_name }}-config"
    - "{{ nginx_config_name }}-shared"
    - "sites-enabled"
    - "conf.d"
  tags: [nginx, config, directories]

# ============================================================
# Étape 4 : Déploiement de proxysocks.conf
# ============================================================

- name: Deploy proxysocks.conf
  ansible.builtin.template:
    src: config/nginx/tcpconf.d/proxysocks.conf.j2
    dest: "{{ nginx_home_directory }}/tcpconf.d/proxysocks.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
  tags: [nginx, config]

# ============================================================
# Étape 5 : Déploiement des configurations (remplace _copy_config.sh)
# ============================================================

- name: Deploy all NGINX configuration files
  ansible.builtin.include_tasks: deploy_config.yml
  tags: [nginx, config]

# ============================================================
# Étape 6 : Déploiement des fichiers statiques (remplace _copy_static.sh)
# ============================================================

- name: Deploy static files
  ansible.builtin.include_tasks: deploy_static.yml
  tags: [nginx, static]

# ============================================================
# Étape 7 : Configuration des certificats (remplace _setup_certificate.sh)
# ============================================================

- name: Setup SSL certificates
  ansible.builtin.include_tasks: setup_certificate.yml
  tags: [nginx, cert]

# ============================================================
# Étape 8 : Validation et reload
# ============================================================

- name: Validate NGINX configuration
  ansible.builtin.command: nginx -t
  register: nginx_test_result
  changed_when: false
  tags: [nginx, validate]

- name: Display validation result
  ansible.builtin.debug:
    var: nginx_test_result
  when: nginx_test_result.rc != 0
  tags: [nginx, validate]

- name: Reload NGINX (Linux)
  ansible.builtin.service:
    name: nginx
    state: reloaded
  when:
    - nginx_test_result.rc == 0
    - ansible_facts['os_family'] != 'Windows'
  tags: [nginx, reload]

- name: Restart NGINX service (Windows)
  ansible.windows.win_service:
    name: nginx
    state: restarted
  when:
    - nginx_test_result.rc == 0
    - ansible_facts['os_family'] == 'Windows'
  tags: [nginx, reload]
```

---

### 🔹 Remplacement de `2-nginx--deploy-cron.sh`

**Fichier Ansible** : `roles/nginx/tasks/deploy_cron.yml`

```yaml
---
# roles/nginx/tasks/deploy_cron.yml

- name: Include OS-specific cron deployment
  ansible.builtin.include_tasks: "deploy_cron_{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [nginx, cron]
```

---

### 🔹 Remplacement de `_copy_config.sh`

**Fichier Ansible** : `roles/nginx/tasks/deploy_config.yml`

```yaml
---
# roles/nginx/tasks/deploy_config.yml
# Remplace complètement _copy_config.sh

- name: Deploy nginx.conf (always overwrite - required for operation)
  ansible.builtin.template:
    src: config/nginx/conf/nginx.conf.j2
    dest: "{{ nginx_home_directory }}/conf/nginx.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
    backup: yes
  tags: [nginx, config, nginx_conf]

- name: Deploy proxysocks.conf (always overwrite - required for operation)
  ansible.builtin.template:
    src: config/nginx/tcpconf.d/proxysocks.conf.j2
    dest: "{{ nginx_home_directory }}/tcpconf.d/proxysocks.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
    backup: yes
  tags: [nginx, config, proxysocks]

- name: Deploy main site configuration (always overwrite - required for operation)
  ansible.builtin.template:
    src: config/nginx/sites-enabled/ampacimon.conf.j2
    dest: "{{ nginx_home_directory }}/sites-enabled/{{ nginx_config_name }}.conf"
    mode: '0644'
    owner: root
    group: root
    validate: "nginx -t -c %s"
    backup: yes
  tags: [nginx, config, site]

- name: Deploy apcm-shared configurations (always overwrite - required for operation)
  ansible.builtin.template:
    src: "config/nginx/apcm-shared/{{ item }}.j2"
    dest: "{{ nginx_home_directory }}/{{ nginx_config_name }}-shared/{{ item }}"
    mode: '0644'
    owner: root
    group: root
  loop:
    - security-headers.shared
    - uptimerobot.shared
  tags: [nginx, config, shared]

- name: Deploy apcm-config configurations (always overwrite - required for operation)
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
  tags: [nginx, config, apcm]

- name: Enable site configuration
  ansible.builtin.file:
    src: "{{ nginx_home_directory }}/sites-enabled/{{ nginx_config_name }}.conf"
    dest: "{{ nginx_home_directory }}/sites-enabled/default.conf"
    state: link
    force: yes
  when: nginx_create_default_link | default(true)
  tags: [nginx, config]
```

**Note** : Contrairement au script original qui demande confirmation, on **écrase toujours** car c'est le comportement attendu en mode automatisé. Si besoin de backup, Ansible le gère avec `backup: yes`.

---

### 🔹 Remplacement de `_copy_static.sh`

**Fichier Ansible** : `roles/nginx/tasks/deploy_static.yml`

```yaml
---
# roles/nginx/tasks/deploy_static.yml
# Remplace complètement _copy_static.sh

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

- name: Set ownership on static files (Linux only)
  ansible.builtin.file:
    path: "{{ static_files_folder }}"
    state: directory
    recurse: yes
    owner: www-data
    group: www-data
  when: ansible_facts['os_family'] != 'Windows'
  tags: [nginx, static]

- name: Set ownership on static files (Windows)
  ansible.windows.win_file:
    path: "{{ static_files_folder }}"
    state: directory
  when: ansible_facts['os_family'] == 'Windows'
  tags: [nginx, static]
```

---

### 🔹 Remplacement de `_setup_certificate.sh`

**Fichier Ansible** : `roles/nginx/tasks/setup_certificate.yml`

```yaml
---
# roles/nginx/tasks/setup_certificate.yml
# Remplace complètement _setup_certificate.sh

# ============================================================
# Étape 1 : Créer le répertoire des certificats
# ============================================================

- name: Create certificates directory
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/certs"
    state: directory
    mode: '0755'
    owner: root
    group: root
  tags: [nginx, cert]

# ============================================================
# Étape 2 : Copier le fichier ffdhe2048.txt
# ============================================================

- name: Deploy DH parameters
  ansible.builtin.copy:
    src: config/nginx/certs/ffdhe2048.txt
    dest: "{{ nginx_home_directory }}/ffdhe2048.txt"
    mode: '0644'
    owner: root
    group: root
  tags: [nginx, cert]

# ============================================================
# Étape 3 : Déployer les certificats (selon le type)
# ============================================================

- name: Deploy self-signed certificate (IP-based)
  community.crypto.openssl_certificate:
    path: "{{ nginx_ssl_cert_path }}"
    privatekey_path: "{{ nginx_ssl_key_path }}"
    csr_path: "{{ nginx_home_directory }}/certs/apcm-cert.csr"
    provider: selfsigned
    selfsigned_not_after: +{{ nginx_cert_validity_days | default(3650) }}d
    selfsigned_digest: sha256
    selfsigned_version: 3
    selfsigned_key_usage:
      - digitalSignature
      - keyEncipherment
    selfsigned_extended_key_usage:
      - serverAuth
    selfsigned_subject:
      C: "{{ nginx_cert_country | default('BE') }}"
      ST: "{{ nginx_cert_state | default('Liegge') }}"
      L: "{{ nginx_cert_locality | default('Loncin') }}"
      O: "{{ nginx_cert_organization | default('Ampacimon') }}"
      OU: "{{ nginx_cert_ou | default('IT') }}"
      CN: "{{ nginx_config_name }}"
    selfsigned_ip:
      - "{{ ext_host_fqdn | ipaddr }}"
  when:
    - nginx_cert_type == 'selfsigned'
    - ext_host_fqdn | ipaddr
  tags: [nginx, cert, selfsigned]

- name: Deploy self-signed certificate (DNS-based)
  community.crypto.openssl_certificate:
    path: "{{ nginx_ssl_cert_path }}"
    privatekey_path: "{{ nginx_ssl_key_path }}"
    csr_path: "{{ nginx_home_directory }}/certs/apcm-cert.csr"
    provider: selfsigned
    selfsigned_not_after: +{{ nginx_cert_validity_days | default(3650) }}d
    selfsigned_digest: sha256
    selfsigned_subject:
      C: "{{ nginx_cert_country | default('BE') }}"
      ST: "{{ nginx_cert_state | default('Liegge') }}"
      L: "{{ nginx_cert_locality | default('Loncin') }}"
      O: "{{ nginx_cert_organization | default('Ampacimon') }}"
      OU: "{{ nginx_cert_ou | default('IT') }}"
      CN: "{{ ext_host_fqdn }}"
    selfsigned_dns:
      - "{{ ext_host_fqdn }}"
  when:
    - nginx_cert_type == 'selfsigned'
    - not (ext_host_fqdn | ipaddr)
  tags: [nginx, cert, selfsigned]

- name: Deploy custom certificate
  ansible.builtin.copy:
    src: "{{ nginx_ssl_cert_source }}"
    dest: "{{ nginx_ssl_cert_path }}"
    mode: '0644'
    owner: root
    group: root
  when:
    - nginx_cert_type == 'custom'
    - nginx_ssl_cert_source is defined
  tags: [nginx, cert, custom]

- name: Deploy custom key
  ansible.builtin.copy:
    src: "{{ nginx_ssl_key_source }}"
    dest: "{{ nginx_ssl_key_path }}"
    mode: '0600'
    owner: root
    group: root
  when:
    - nginx_cert_type == 'custom'
    - nginx_ssl_key_source is defined
  tags: [nginx, cert, custom]

- name: Warn if custom cert not provided
  ansible.builtin.debug:
    msg: >
      WARNING: Custom certificate mode selected but no source provided.
      You must manually deploy certificate to {{ nginx_ssl_cert_path }}
      and key to {{ nginx_ssl_key_path }}
  when:
    - nginx_cert_type == 'custom'
    - (nginx_ssl_cert_source is not defined or nginx_ssl_key_source is not defined)
  tags: [nginx, cert, custom]

# ============================================================
# Étape 4 : Configurer les permissions (Linux)
# ============================================================

- name: Set certificate permissions (Linux)
  ansible.builtin.file:
    path: "{{ nginx_home_directory }}/certs"
    state: directory
    recurse: yes
    mode: '0640'
    owner: root
    group: root
  when: ansible_facts['os_family'] != 'Windows'
  tags: [nginx, cert, permissions]
```

---

### 🔹 Remplacement de `_create-cronjob.sh` (Linux)

**Fichier Ansible** : `roles/nginx/tasks/deploy_cron_linux.yml`

```yaml
---
# roles/nginx/tasks/deploy_cron_linux.yml
# Remplace complètement _create-cronjob.sh

# ============================================================
# Étape 1 : Créer l'utilisateur de maintenance
# ============================================================

- name: Create maintenance user
  ansible.builtin.user:
    name: "{{ maintenance_user | default('Scriptuser') }}"
    state: present
    system: yes
    shell: /bin/bash
    home: "/home/{{ maintenance_user | default('Scriptuser') }}"
    create_home: yes
  tags: [nginx, cron, user]

- name: Add maintenance user to root group
  ansible.builtin.user:
    name: "{{ maintenance_user | default('Scriptuser') }}"
    groups: root
    append: yes
  tags: [nginx, cron, user]

- name: Add maintenance user to adm group
  ansible.builtin.user:
    name: "{{ maintenance_user | default('Scriptuser') }}"
    groups: adm
    append: yes
  tags: [nginx, cron, user]

# ============================================================
# Étape 2 : Créer les répertoires de maintenance
# ============================================================

- name: Create maintenance directories
  ansible.builtin.file:
    path: "/apcm-maintenance/{{ item }}"
    state: directory
    mode: '0755'
    owner: "{{ maintenance_user | default('Scriptuser') }}"
    group: "{{ maintenance_user | default('Scriptuser') }}"
  loop:
    - ""
    - data
    - bin
  tags: [nginx, cron, directories]

# ============================================================
# Étape 3 : Vérifier les permissions sur les logs
# ============================================================

- name: Ensure maintenance user can read NGINX logs
  ansible.builtin.file:
    path: "{{ nginx_log_directory }}"
    state: directory
    recurse: yes
    mode: '0750'
    owner: root
    group: adm
  tags: [nginx, cron, permissions]

# ============================================================
# Étape 4 : Déployer les fichiers de configuration
# ============================================================

- name: Deploy maintenance.ini
  ansible.builtin.template:
    src: conf/apcm-maintenance/maintenance.ini.j2
    dest: /apcm-maintenance/data/maintenance.ini
    mode: '0600'
    owner: "{{ maintenance_user | default('Scriptuser') }}"
    group: "{{ maintenance_user | default('Scriptuser') }}"
  tags: [nginx, cron, config]

- name: Deploy exportNGINX.ini
  ansible.builtin.template:
    src: conf/apcm-maintenance/exportNGINX.ini.j2
    dest: /apcm-maintenance/data/exportNGINX.ini
    mode: '0600'
    owner: "{{ maintenance_user | default('Scriptuser') }}"
    group: "{{ maintenance_user | default('Scriptuser') }}"
  tags: [nginx, cron, config]

# ============================================================
# Étape 5 : Déployer le script d'export des logs
# ============================================================

- name: Deploy exportNGINXLogs.sh
  ansible.builtin.copy:
    src: scripts/bash/cron/exportNGINXLogs.sh
    dest: /apcm-maintenance/exportNGINXLogs.sh
    mode: '0700'
    owner: "{{ maintenance_user | default('Scriptuser') }}"
    group: "{{ maintenance_user | default('Scriptuser') }}"
  tags: [nginx, cron, script]

# ============================================================
# Étape 6 : Créer la tâche cron
# ============================================================

- name: Create cron job for NGINX log export
  ansible.builtin.cron:
    name: "Export NGINX logs"
    user: "{{ maintenance_user | default('Scriptuser') }}"
    job: "cd /apcm-maintenance && /apcm-maintenance/exportNGINXLogs.sh"
    minute: "10"
    hour: "0"
    state: present
  tags: [nginx, cron]
```

---

### 🔹 Remplacement de `_create-schtask.ps1` (Windows)

**Fichier Ansible** : `roles/nginx/tasks/deploy_cron_windows.yml`

```yaml
---
# roles/nginx/tasks/deploy_cron_windows.yml
# Remplace complètement _create-schtask.ps1

# ============================================================
# Étape 1 : Créer les répertoires de maintenance
# ============================================================

- name: Create maintenance directories
  ansible.windows.win_file:
    path: "{{ win_maintenance_path }}\{{ item }}"
    state: directory
  loop:
    - ""
    - data
    - bin
    - data\protected
  tags: [nginx, cron, directories]

# ============================================================
# Étape 2 : Créer l'utilisateur de maintenance
# ============================================================

- name: Create maintenance user
  ansible.windows.win_user:
    name: "{{ win_maintenance_user | default('Scriptuser') }}"
    password: "{{ win_maintenance_password | default('P@ssw0rd123!') }}"
    state: present
    password_never_expires: yes
    groups:
      - Administrators
  tags: [nginx, cron, user]

# ============================================================
# Étape 3 : Monter le partage réseau (si nécessaire)
# ============================================================

- name: Mount network share for datadir
  community.windows.win_smb_mapping:
    remote_path: "{{ nginx_datadir }}"
    local_path: "Z:"
    username: "{{ nginx_datadir_user | default(omit) }}"
    password: "{{ nginx_datadir_password | default(omit) }}"
    state: mapped
  when:
    - nginx_datadir.startswith('\\')
    - nginx_datadir_user != ''
  tags: [nginx, cron, smb]

# ============================================================
# Étape 4 : Déployer les fichiers de configuration
# ============================================================

- name: Deploy maintenance.ini
  ansible.windows.win_template:
    src: conf/apcm-maintenance/maintenance.ini.j2
    dest: "{{ win_maintenance_path }}\data\maintenance.ini"
  tags: [nginx, cron, config]

- name: Deploy exportNGINX.ini
  ansible.windows.win_template:
    src: conf/apcm-maintenance/exportNGINX.ini.j2
    dest: "{{ win_maintenance_path }}\data\exportNGINX.ini"
  tags: [nginx, cron, config]

# ============================================================
# Étape 5 : Déployer les scripts PowerShell
# ============================================================

- name: Deploy PowerShell scripts
  ansible.windows.win_copy:
    src: "scripts/posh/{{ item }}"
    dest: "{{ win_maintenance_path }}\{{ item }}"
  loop:
    - exportNGINXLogs.ps1
    - rotateNGINXLogs.ps1
    - onDemandTask.ps1
  tags: [nginx, cron, script]

# ============================================================
# Étape 6 : Créer les tâches planifiées
# ============================================================

- name: Create scheduled task for log rotation
  ansible.windows.win_scheduled_task:
    name: apcm-maintenance-rotatenginxLogs
    description: "Rotate NGINX logs daily at midnight"
    actions:
      - path: powershell.exe
        arguments: "-noprofile -executionpolicy bypass -file \"{{ win_maintenance_path }}\rotateNGINXLogs.ps1\""
    triggers:
      - type: daily
        start_time: "00:00"
        enabled: yes
    user: SYSTEM
    state: present
  tags: [nginx, cron, rotation]

- name: Create on-demand scheduled task
  ansible.windows.win_scheduled_task:
    name: apcm-maintenance
    description: "On-demand maintenance task triggered by EventLog"
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
    password: "{{ win_maintenance_password | default('P@ssw0rd123!') }}"
    state: present
  tags: [nginx, cron, ondemand]

- name: Ensure EventLog source exists
  ansible.windows.win_eventlog:
    name: Application
    source: ADR
    state: present
  tags: [nginx, cron, eventlog]

# ============================================================
# Étape 7 : Configurer les permissions
# ============================================================

- name: Set permissions on maintenance directory
  ansible.windows.win_acl:
    path: "{{ win_maintenance_path }}"
    user: "{{ win_maintenance_user | default('Scriptuser') }}"
    permissions: FullControl
    type: directory
    state: present
    inherit: ContainerInherit, ObjectInherit
    propagation: InheritOnly
  tags: [nginx, cron, permissions]
```

---

## 📊 Mapping des Variables

### Variables pour les Scripts de Configuration

```yaml
# group_vars/all.yml

# ============================================================
# Utilisateur de Maintenance
# ============================================================
maintenance_user: "Scriptuser"  # Linux
win_maintenance_user: "Scriptuser"  # Windows
win_maintenance_password: "{{ vault_win_maintenance_password }}"  # À mettre dans vault
win_maintenance_path: "C:\\apcm-maintenance"

# ============================================================
# Chemins NGINX
# ============================================================
nginx_home_directory: "/etc/nginx"
nginx_config_name: "ampacimon"
nginx_log_directory: "/var/log/nginx"
static_files_folder: "/var/www/{{ nginx_config_name }}"

# ============================================================
# Répertoire des Données
# ============================================================
nginx_datadir: "/opt/adr/data"
nginx_datadir_user: ""  # Optionnel
nginx_datadir_password: ""  # Optionnel

# ============================================================
# Certificats SSL
# ============================================================
nginx_cert_type: "selfsigned"  # selfsigned, custom, existing
nginx_ssl_cert_source: ""  # Chemin vers certificat custom
nginx_ssl_key_source: ""  # Chemin vers clé custom
nginx_ssl_cert_path: "{{ nginx_home_directory }}/certs/apcm-cert.crt"
nginx_ssl_key_path: "{{ nginx_home_directory }}/certs/apcm-cert.key"
nginx_cert_validity_days: 3650  # 10 ans
nginx_cert_country: "BE"
nginx_cert_state: "Liegge"
nginx_cert_locality: "Loncin"
nginx_cert_organization: "Ampacimon"
nginx_cert_ou: "IT"
```

---

## 📝 Checklist de Migration

### ✅ À Faire pour NGINX

- [ ] **Préparation**
  - [ ] Créer la structure `roles/nginx/templates/config/nginx/`
  - [ ] Copier tous les fichiers de `resources/config/nginx/` vers `templates/`
  - [ ] Convertir chaque fichier en template Jinja2 (remplacer `@token@` par `{{ variable }}`)
  - [ ] Créer les fichiers `*.j2` pour maintenance.ini et exportNGINX.ini

- [ ] **Templates**
  - [ ] `config/nginx/conf/nginx.conf.j2`
  - [ ] `config/nginx/sites-enabled/ampacimon.conf.j2`
  - [ ] `config/nginx/tcpconf.d/proxysocks.conf.j2`
  - [ ] `config/nginx/apcm-config/certificates.config.j2`
  - [ ] `config/nginx/apcm-config/custom-rules.config.j2`
  - [ ] `config/nginx/apcm-config/app-access.config.j2`
  - [ ] `config/nginx/apcm-config/admin-access.config.j2`
  - [ ] `config/nginx/apcm-config/api-access.config.j2`
  - [ ] `config/nginx/apcm-shared/security-headers.shared.j2`
  - [ ] `config/nginx/apcm-shared/uptimerobot.shared.j2`
  - [ ] `conf/apcm-maintenance/maintenance.ini.j2`
  - [ ] `conf/apcm-maintenance/exportNGINX.ini.j2`

- [ ] **Tâches Ansible**
  - [ ] `tasks/setup_linux.yml` (remplace installation Linux)
  - [ ] `tasks/setup_windows.yml` (remplace installation Windows)
  - [ ] `tasks/deploy_config.yml` (remplace `_copy_config.sh`)
  - [ ] `tasks/deploy_static.yml` (remplace `_copy_static.sh`)
  - [ ] `tasks/setup_certificate.yml` (remplace `_setup_certificate.sh`)
  - [ ] `tasks/deploy_cron_linux.yml` (remplace `_create-cronjob.sh`)
  - [ ] `tasks/deploy_cron_windows.yml` (remplace `_create-schtask.ps1`)
  - [ ] `tasks/main.yml` (intègre tout)

- [ ] **Variables**
  - [ ] Définir toutes les variables dans `group_vars/all.yml`
  - [ ] Créer `group_vars/all_secrets.yml` pour les secrets (encrypted)
  - [ ] Définir les defaults dans `roles/nginx/defaults/main.yml`

- [ ] **Tests**
  - [ ] Tester l'installation sur une machine propre
  - [ ] Tester le déploiement des configurations
  - [ ] Tester le déploiement des certificats
  - [ ] Tester le déploiement des tâches cron
  - [ ] Valider avec `nginx -t`

- [ ] **Nettoyage**
  - [ ] Supprimer `TMP-CONFIG/` du repo
  - [ ] Supprimer les références aux scripts dans le README
  - [ ] Mettre à jour la documentation
  - [ ] Commit et merge

---

## 💡 Conseils et Bonnes Pratiques

### 1. **Conversion des Fichiers en Templates**

**Processus recommandé** :
```bash
# Pour chaque fichier dans resources/config/nginx/
find resources/config/nginx/ -type f -name "*.conf" -o -name "*.config" -o -name "*.shared" | while read file; do
    # Créer le répertoire cible
    target_dir=$(echo "$file" | sed 's|resources/config/|templates/config/|' | sed 's|\..*$||')
    mkdir -p "roles/nginx/templates/$target_dir"
    
    # Copier le fichier
    cp "$file" "roles/nginx/templates/$target_dir/$(basename $file).j2"
    
    # Remplacer les tokens @...@ par {{ ... }}
    sed -i 's/@\([a-zA-Z0-9._-]*\)/{{\1}}/g' "roles/nginx/templates/$target_dir/$(basename $file).j2"
done
```

**Exemple de conversion** :
```bash
# Avant
upstream @nginx.config.name@_keycloak {
  server @keycloak.host.fqdn@:@keycloak.https.port@;
}

# Après
upstream {{ nginx_config_name }}_keycloak {
  server {{ keycloak_host_fqdn }}:{{ keycloak_https_port }};
}
```

### 2. **Gestion des Variables**

**Hiérarchie recommandée** :
```
1. group_vars/all.yml          # Variables communes à tous les environnements
2. group_vars/<env>/main.yml  # Overrides par environnement (dev, staging, prod)
3. roles/nginx/defaults/      # Valeurs par défaut
4. Extra vars (-e)            # Overrides temporaires
```

**Exemple** :
```yaml
# roles/nginx/defaults/main.yml
nginx_config_name: "ampacimon"
nginx_home_directory: "/etc/nginx"
keycloak_host_fqdn: "localhost"

# group_vars/dev/main.yml
nginx_config_name: "ampacimon-dev"
keycloak_host_fqdn: "auth.dev.example.com"

# group_vars/prod/main.yml
nginx_config_name: "ampacimon"
keycloak_host_fqdn: "auth.example.com"
```

### 3. **Gestion des Secrets**

**Utiliser Ansible Vault** :
```bash
# Encrypter un fichier
ansible-vault encrypt group_vars/all_secrets.yml

# Éditer un fichier encrypté
ansible-vault edit group_vars/all_secrets.yml

# Exécuter un playbook avec vault
ansible-playbook deploy.yml --ask-vault-pass
```

**Exemple de fichier secrets** :
```yaml
# group_vars/all_secrets.yml (encrypted)
win_maintenance_password: "MyS3cr3tP@ssw0rd"
nginx_ssl_cert_source: "/path/to/custom.crt"
nginx_ssl_key_source: "/path/to/custom.key"
nginx_datadir_user: "domain\\user"
nginx_datadir_password: "Sh@r3P@ss"
```

### 4. **Validation des Configurations**

**Utiliser le paramètre `validate`** :
```yaml
- name: Deploy nginx.conf
  ansible.builtin.template:
    src: config/nginx/conf/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    validate: "nginx -t -c %s"
```

**Créer une tâche de validation dédiée** :
```yaml
- name: Validate all NGINX configurations
  ansible.builtin.command: nginx -t
  register: nginx_validation
  changed_when: false
  check_mode: no

- name: Fail if NGINX validation fails
  ansible.builtin.fail:
    msg: "NGINX configuration is invalid: {{ nginx_validation.stderr }}"
  when: nginx_validation.rc != 0
```

### 5. **Gestion des Différences entre Environnements**

**Utiliser des conditions** :
```yaml
- name: Deploy production-specific configuration
  ansible.builtin.template:
    src: config/nginx/prod-specific.conf.j2
    dest: /etc/nginx/conf.d/prod.conf
  when: environment == 'prod'
```

**Utiliser des fichiers de variables séparés** :
```
group_vars/
├── all.yml              # Commun
├── dev.yml              # Dev-specific
├── staging.yml          # Staging-specific
└── prod.yml             # Prod-specific
```

---

## 🚀 Commandes Utiles

### Pour convertir les fichiers

```bash
# Trouver tous les tokens dans les fichiers
find TMP-CONFIG/sources/nginx -type f -name "*.conf" -o -name "*.config" | \
  xargs grep -oh '@[a-zA-Z0-9._-]*@' | sort -u

# Compter le nombre de fichiers à convertir
find TMP-CONFIG/sources/nginx/apcm-nginx-bundle/resources/config -type f | \
  grep -v "Zone.Identifier" | wc -l

# Vérifier les permissions après déploiement
ansible all -m command -a "nginx -t" -i inventory/hosts.yml
```

### Pour tester la migration

```bash
# Test en local avec les templates
ansible-playbook deploy.yml --limit localhost --tags nginx

# Test de la validation NGINX
ansible-playbook deploy.yml --limit localhost --tags "nginx,validate"

# Test complet
ansible-playbook deploy.yml --ask-vault-pass
```

---

## 🔐 Intégration Ansible Vault - Gestion des Secrets

**IMPÉRATIF** : Tous les mots de passe, clés API, certificats et secrets doivent être stockés dans **Ansible Vault** et jamais en clair dans les fichiers de configuration ou les playbooks.

---

### 1. Architecture des Fichiers Vault

```
ansible/
├── group_vars/
│   ├── all.yml                    # Variables NON sensibles (public)
│   ├── all_secrets.yml            # Variables sensibles (CHIFFRÉ)
│   ├── dev_secrets.yml            # Secrets spécifiques dev (CHIFFRÉ)
│   ├── staging_secrets.yml        # Secrets spécifiques staging (CHIFFRÉ)
│   └── prod_secrets.yml           # Secrets spécifiques prod (CHIFFRÉ)
└── host_vars/
    └── <hostname>_secrets.yml     # Secrets spécifiques hôte (CHIFFRÉ)
```

**Bonnes pratiques** :
- Un fichier Vault par environnement (dev/staging/prod)
- Utiliser `group_vars/all_secrets.yml` pour les secrets communs à tous les environnements
- Utiliser `host_vars/<host>_secrets.yml` pour les secrets spécifiques à un hôte
- Ne JAMAIS commiter de fichiers non chiffrés contenant des secrets

---

### 2. Structure des Secrets pour NGINX

#### **Fichier `group_vars/all_secrets.yml` (à chiffrer)**

```yaml
# ============================================================
# NGINX - SSL Certificates
# ============================================================
nginx_ssl_cert_content: |
  {{ vault_nginx_ssl_cert | indent(2) }}
nginx_ssl_key_content: |
  {{ vault_nginx_ssl_key | indent(2) }}

# Chemin vers certificats existants (si nginx_cert_type: custom/existing)
nginx_ssl_cert_source: "/path/to/production/cert.pem"
nginx_ssl_key_source: "/path/to/production/key.pem"

# ============================================================
# NGINX - Basic Auth Credentials
# ============================================================
# Si utilisation de l'authentification basic
nginx_basic_auth_users:
  - username: "admin"
    password: "{{ vault_nginx_basic_auth_admin_password }}"
  - username: "monitor"
    password: "{{ vault_nginx_basic_auth_monitor_password }}"

# ============================================================
# NGINX - Data Directory Credentials
# ============================================================
nginx_datadir_user: "{{ vault_nginx_datadir_username }}"
nginx_datadir_password: "{{ vault_nginx_datadir_password }}"

# ============================================================
# NGINX - Maintenance Credentials
# ============================================================
win_maintenance_password: "{{ vault_win_maintenance_password }}"
```

#### **Fichier `group_vars/prod_secrets.yml` (exemple production)**

```yaml
# ============================================================
# NGINX - Production SSL Certificates
# ============================================================
vault_nginx_ssl_cert: |
  -----BEGIN CERTIFICATE-----
  MII... (certificat production)
  -----END CERTIFICATE-----

vault_nginx_ssl_key: |
  -----BEGIN PRIVATE KEY-----
  MII... (clé privée production)
  -----END PRIVATE KEY-----

# ============================================================
# NGINX - Production Credentials
# ============================================================
vault_nginx_basic_auth_admin_password: "{{ random_password_32_chars }}"
vault_nginx_basic_auth_monitor_password: "{{ random_password_32_chars }}"
vault_nginx_datadir_username: "prod\\svc-nginx"
vault_nginx_datadir_password: "{{ random_password_32_chars }}"
vault_win_maintenance_password: "{{ random_password_32_chars }}"
```

---

### 3. Commandes de Chiffrement/Déchiffrement

#### **Créer un nouveau fichier Vault**
```bash
# Créer et éditer un fichier chiffré
ansible-vault create group_vars/prod_secrets.yml

# ou utiliser un éditeur spécifique
ansible-vault edit group_vars/prod_secrets.yml

# Créer un fichier chiffré à partir d'un fichier existant
ansible-vault encrypt group_vars/all_secrets.yml
```

#### **Modifier un fichier Vault existant**
```bash
ansible-vault edit group_vars/prod_secrets.yml
```

#### **Déchiffrer un fichier pour vérification**
```bash
# Déchiffrer temporairement pour visualisation
ansible-vault view group_vars/prod_secrets.yml

# Déchiffrer un fichier
ansible-vault decrypt group_vars/prod_secrets.yml
```

#### **Changer le mot de passe du Vault**
```bash
ansible-vault rekey group_vars/prod_secrets.yml
```

---

### 4. Intégration avec les Playbooks

#### **Exécution avec Vault**

```bash
# Exécuter avec demande interactive du mot de passe
ansible-playbook deploy.yml --ask-vault-pass

# Utiliser un fichier de mot de passe
ansible-playbook deploy.yml --vault-password-file ~/.vault_pass.txt

# Utiliser une variable d'environnement
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass.txt
ansible-playbook deploy.yml
```

#### **Exemple de playbook avec Vault**

```yaml
---
- name: Deploy NGINX Configuration
  hosts: nginx_servers
  vars_files:
    - group_vars/all.yml
    - group_vars/all_secrets.yml  # Chiffré avec Vault
  
  tasks:
    - name: Include secrets for current environment
      ansible.builtin.include_vars:
        file: "group_vars/{{ environment }}_secrets.yml"
      no_log: true
      when: environment is defined
      
    - name: Deploy nginx.conf with SSL
      ansible.builtin.template:
        src: config/nginx/conf/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
        mode: '0644'
        validate: "nginx -t -c %s"
      no_log: true  # Ne pas logger le contenu sensible
```

---

### 5. Bonnes Pratiques de Sécurité

#### **Dans les playbooks**

```yaml
# TOUJOURS utiliser no_log: true pour les tâches manipulant des secrets
- name: Create SSL certificate
  community.crypto.openssl_certificate:
    path: "{{ nginx_ssl_cert_path }}"
    privatekey_path: "{{ nginx_ssl_key_path }}"
    csr_path: /tmp/nginx.csr
    provider: selfsigned
  no_log: true

# Éviter d'afficher les secrets dans les messages
- name: Set fact with sensitive data
  ansible.builtin.set_fact:
    db_password: "{{ vault_db_password }}"
  no_log: true

# Utiliser register avec no_log pour les commandes sensibles
- name: Check certificate
  ansible.builtin.command: openssl x509 -in "{{ nginx_ssl_cert_path }}" -text -noout
  register: cert_info
  no_log: true
  changed_when: false
```

#### **Permissions des fichiers**

```yaml
# TOUJOURS définir des permissions strictes sur les fichiers sensibles
- name: Deploy SSL key
  ansible.builtin.copy:
    content: "{{ nginx_ssl_key_content }}"
    dest: "{{ nginx_ssl_key_path }}"
    mode: '0600'  # Lecteur/écriture uniquement pour le propriétaire
    owner: root
    group: root
  no_log: true

- name: Deploy configuration with sensitive data
  ansible.builtin.template:
    src: config/nginx/sites-enabled/ampacimon.conf.j2
    dest: /etc/nginx/sites-enabled/ampacimon.conf
    mode: '0640'  # Propriétaire lecture/écriture, groupe lecture
    owner: root
    group: root
  no_log: true
```

#### **Gestion des variables sensibles**

```yaml
# TOUJOURS utiliser des variables séparées pour les secrets
# MAUVAIS:
nginx_config: |
  server {
    ssl_certificate_key /path/to/key.pem;  # Le contenu serait visible
  }

# BON:
nginx_ssl_key_path: "/etc/nginx/certs/key.pem"

# Dans le template:
# ssl_certificate_key {{ nginx_ssl_key_path }};

# Le fichier lui-même est déployé séparément avec mode: 0600
```

---

### 6. Génération de Mots de Passe Aléatoires

#### **Utiliser le module `community.general.random_string`**

```yaml
- name: Generate random passwords
  community.general.random_string:
    length: 32
    special: true
    upper: true
    lower: true
    digits: true
  register: generated_passwords
  no_log: true

- name: Store generated passwords in Vault
  ansible.builtin.lineinfile:
    path: group_vars/{{ environment }}_secrets.yml
    line: "vault_nginx_password: {{ generated_passwords.string | to_json }}"
    insertafter: "^# Generated passwords"
  no_log: true
  delegate_to: localhost
  run_once: true
```

#### **Commande CLI pour générer des mots de passe**

```bash
# Générer un mot de passe aléatoire de 32 caractères
openssl rand -base64 24

# Générer avec caractères spéciaux
openssl rand -base64 24 | tr '+/' '-_' | head -c32

# Avec ansible
ansible localhost -e "msg={{ lookup('community.general.random_string', length=32, special=true) }}" -m debug
```

---

### 7. Audit de Sécurité

#### **Checklist avant commit**

- [ ] Tous les mots de passe sont dans des fichiers `.yml` chiffrés avec Vault
- [ ] Aucun secret en clair dans les playbooks ou templates
- [ ] Les templates utilisent des variables et non des valeurs hardcodées
- [ ] Les tâches manipulant des secrets ont `no_log: true`
- [ ] Les fichiers sensibles ont des permissions restreintes (mode: '0600' ou '0640')
- [ ] Les fichiers Vault sont dans `.gitignore`
- [ ] Les secrets sont spécifiques à chaque environnement (dev/staging/prod)
- [ ] Rotation des mots de passe documentée

#### **Vérification des secrets non chiffrés**

```bash
# Rechercher des mots de passe potentiels dans les fichiers
# (à exécuter avant de commiter)
grep -rE "password|passwd|secret|api_key|token|private" \
  --include="*.yml" --include="*.yaml" --include="*.j2" \
  --exclude-dir=group_vars --exclude-dir=host_vars \
  ansible/ roles/ playbook/

# Rechercher des IP ou URLs hardcodées
grep -rE "http://|https://|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" \
  --include="*.yml" --include="*.j2" \
  ansible/ roles/
```

#### **Configuration Git pour éviter les commits accidentels**

```bash
# Ajouter un pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if git diff --cached --name-only | grep -E '\.(secrets\.yml|vault\.yml)$'; then
  echo "ERROR: Attempting to commit encrypted files!"
  echo "Use: git add <specific-files> and avoid committing Vault files"
  exit 1
fi
EOF
chmod +x .git/hooks/pre-commit
```

---

## 📚 Références

- [Ansible Template Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible File Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Ansible Cron Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/cron_module.html)
- [Ansible User Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/user_module.html)
- [Community Crypto Collection](https://docs.ansible.com/ansible/latest/collections/community/crypto/index.html)
- [OpenSSL Certificate Module](https://docs.ansible.com/ansible/latest/collections/community/crypto/openssl_certificate_module.html)
