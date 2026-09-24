# Migration Payara : Remplacement des Scripts par Ansible

## 📋 Contexte

Le déploiement **Payara** est le plus complexe des trois composants (NGINX, Keycloak, Payara).

**Bundle analysé** : `apcm-payara-bundle-5.82.0-4.0.11-payara-bundle` (Payara 5.82.0)

---

## 🔍 Analyse des Composants Actuels

### Structure du Bundle Payara

```
apcm-payara-bundle/
├── prepare-config.sh              # Appelle Ant pour filtrer les tokens
├── build.xml                      # Définition des tâches Ant
├── 1-payara--setup.sh             # Script principal d'installation
├── 2-payara--deploy-front-cron.sh # Déploiement tâches cron (frontend)
├── 2-payara--deploy-backend-cron.sh# Déploiement tâches cron (backend)
├── t1a.sh                         # Script de test ?
├── t1s.sh                         # Script de test ?
├── t1au.sh                        # Script de test ?
├── startDomain.sh                 # Démarrage du domaine
├── create-api-client.sh          # Création client API
├── clear-passwords.sh             # Nettoyage des mots de passe
├── x-payara--remove-service.sh    # Suppression du service
├── profiles/
│   └── template/
│       └── config.properties      # Variables par défaut (key=value)
├── resources/
│   ├── config/                     # Fichiers de configuration
│   │   ├── logback.xml            # Configuration Logback
│   │   ├── front-mail.xml         # Config mail frontend
│   │   ├── server-mail.xml        # Config mail backend
│   │   ├── asadmin-common.txt     # Commandes asadmin communes
│   │   └── ...
│   ├── bash-scripts/              # Scripts de configuration
│   │   ├── _setup-variables.sh    # Définition des variables
│   │   ├── _setup-precheck.sh      # Pré-vérifications
│   │   ├── _setup-postcheck.sh     # Post-vérifications
│   │   ├── _setup-server.sh        # Configuration serveur (backend)
│   │   ├── _setup-front.sh         # Configuration frontend
│   │   ├── _create-front-cronjobs.sh # Création tâches cron frontend
│   │   ├── _create-server-cronjobs.sh # Création tâches cron backend
│   │   ├── _log_function.sh        # Fonction de logging
│   │   └── ...
│   ├── mongo/                     # Scripts MongoDB
│   │   ├── latest/
│   │   │   ├── 1-create-default-collection.js
│   │   │   └── 2-create-users-roles.js
│   │   └── 3.3/
│   │       ├── 1-create-default-collection.js
│   │       └── 2-create-users-roles.js
│   ├── sql/                       # Scripts SQL
│   │   └── latest/
│   │       ├── postgresql/
│   │       │   └── 1-create-database-20260529.sql
│   │       └── sqlserver/
│   │           └── 1-create-database-20260529-ms.sql
│   └── services/                  # Services
│       └── overrides.conf          # Override systemd
└── payara5/                       # Distribution Payara
    ├── bin/                       # Scripts asadmin
    ├── glassfish/                 # Structure GlassFish
    └── ...
```

### Mécanisme de Filtrage (Ant)

Le script `prepare-config.sh` appelle Ant qui :
1. Copie les fichiers binaires sans filtrage
2. Charge `profiles/<profile>/config.properties` comme filtre
3. **Ajoute des filtres supplémentaires** :
   - `fish.home.directory=${basedir}/payara5`
   - `buildprofile=${profile}`
4. Copie tous les autres fichiers **AVEC filtrage** (remplace `@token@`)
5. **Rend les scripts bash exécutables**

### Spécificités Payara

| **Aspect** | **Détails** |
|------------|-------------|
| **Types de déploiement** | Frontend, Backend, SingleInstance |
| **Ports** | Différents pour chaque type (admin, http, https, jmx, etc.) |
| **Base de données** | PostgreSQL, MongoDB, MS-SQL |
| **Cluster** | Support du clustering (Hazelcast) |
| **Services externes** | Intégration avec Keycloak, TWC, CloudLoop, Hawkbit |

---

## 📦 Scripts à Remplacer

### 1️⃣ `prepare-config.sh` + Ant + `build.xml`

**Fonction** : Filtre les tokens `@...@` dans les fichiers de configuration.

**Spécificités Payara** :
- Ajoute des filtres supplémentaires : `fish.home.directory` et `buildprofile`
- Rend les scripts générés exécutables

**Remplacement** :
- ✅ **Templates Jinja2** pour chaque fichier de configuration
- ✅ **Variables centralisées** dans `group_vars/all.yml`
- ✅ **Module `template`** d'Ansible pour le rendu

---

### 2️⃣ `1-payara--setup.sh` (Script Principal d'Installation)

Ce script est **le plus complexe** avec plus de 300 lignes. Voici son analyse détaillée.

#### **Structure du Script**

**1. Initialisation**
```bash
currentdir=$(pwd)
logfile=$currentdir/bundle_log/$(date +"%Y-%m-%dT%H%M%S").log
. $currentdir/generated/bash-scripts/_log_function.sh

DOMAIN_NAME="ampacimon-domain"
PAYARA_HOME="payara5"
ASADMIN=${PAYARA_HOME}/bin/asadmin
ADMIN_PASSWORD="admin"
```

**2. Sélection du type de déploiement**
```bash
PS3="Select your deployment option: "
options=("Frontend" "Backend" "SingleInstance")
select opt in "${options[@]}"; do
    case $opt in
        "Frontend" ) echo "Deploying Frontend server"; break;;
        "Backend" ) echo "Deploying Backend server"; break;;
        "SingleInstance" ) echo "Deploying single instance server"; break;;
        *) echo "Invalid option";;
    esac
done
```

**3. Import des variables et pré-vérifications**
```bash
source ./generated/bash-scripts/_setup-variables.sh
source ./generated/bash-scripts/_setup-precheck.sh

read -p "Do you want to continue ? (y/n) " -n 1 -re
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi
```

**4. Création du domaine**
```bash
# Arrêt et suppression du domaine existant
${ASADMIN} --host localhost --port ${ADMIN_PORT} stop-domain ${DOMAIN_NAME}
${ASADMIN} --host localhost --port ${ADMIN_PORT} delete-domain ${DOMAIN_NAME}

# Suppression du service
source ./generated/bash-scripts/_setup-remove-service.sh

# Création du nouveau domaine
${ASADMIN} create-domain \
  --adminport ${ADMIN_PORT} \
  --domainproperties domain.instancePort=${HTTP_PORT}:http.ssl.port=${HTTPS_PORT}:... \
  --template ${PAYARA_HOME}/glassfish/common/templates/gf/production-domain.jar \
  --user admin \
  --nopassword \
  --keytooloptions CN=${SERVICES_URL} \
  ${DOMAIN_NAME}
```

**5. Démarrage du domaine**
```bash
${ASADMIN} start-domain ${DOMAIN_NAME}
```

**6. Configuration de base**
```bash
# Tuning Payara
${ASADMIN} multimode --file resources/bash-scripts/asadmin-common.txt

# Copie de l'AuditModule
cp -r classes/ ${PAYARA_HOME}/glassfish/domains/${DOMAIN_NAME}/lib/

# Copie de logback.xml
cp generated/config/logback.xml ${PAYARA_HOME}/glassfish/domains/${DOMAIN_NAME}/config/

# Copie du favicon et personnalisation
cp resources/favicon.ico ${PAYARA_HOME}/glassfish/domains/${DOMAIN_NAME}/docroot/
cp resources/index.html ${PAYARA_HOME}/glassfish/domains/${DOMAIN_NAME}/docroot/
rm -rf ${PAYARA_HOME}/glassfish/domains/${DOMAIN_NAME}/docroot/{js,fonts,img,css}
```

**7. Configuration Mail**
```bash
${ASADMIN} add-resources ${MAIL_CONFIG}
${ASADMIN} set resources.mail-resource.mail/sender.debug=false
```

**8. Configuration RMI**
```bash
${ASADMIN} create-jvm-options "-Djava.rmi.server.hostname=${SERVICES_URL_RMI}"
```

**9. Configuration spécifique par type**
```bash
if [[ "$opt" == "Backend" || "$opt" == "SingleInstance" ]]; then
    source ./generated/bash-scripts/_setup-server.sh
fi
if [[ "$opt" == "Frontend" || "$opt" == "SingleInstance" ]]; then
    source ./generated/bash-scripts/_setup-front.sh
fi
```

**10. Configuration Admin**
```bash
# Changement du mot de passe admin
printf "AS_ADMIN_PASSWORD=\nAS_ADMIN_NEWPASSWORD=${ADMIN_PASSWORD}" > changepasswordfile
${ASADMIN} --user admin --passwordfile changepasswordfile change-admin-password
rm changepasswordfile

# Activation de secure-admin
printf "AS_ADMIN_PASSWORD=${ADMIN_PASSWORD}" > passwordfile
${ASADMIN} --user admin --passwordfile passwordfile enable-secure-admin
rm passwordfile
```

**11. Création des aliases de mots de passe**
```bash
# Pour Backend
${ASADMIN} --passwordfile generated/secrets/apcm-service-phoenix-file create-password-alias apcm-service-phoenix-password
${ASADMIN} --passwordfile generated/secrets/apcm-mail-file create-password-alias apcm-mail-password
${ASADMIN} --passwordfile generated/secrets/apcm-mongo-pho-file create-password-alias apcm-mongo-pho-password
${ASADMIN} --passwordfile generated/secrets/apcm-mongo-adg-file create-password-alias apcm-mongo-adg-password
${ASADMIN} --passwordfile generated/secrets/apcm-dbpool-file create-password-alias apcm-dbpool-password
${ASADMIN} --passwordfile generated/secrets/apcm-service-twc-file create-password-alias apcm-service-twc-api-key
${ASADMIN} --passwordfile generated/secrets/apcm-service-cloudloop-file create-password-alias apcm-service-cloudloop-api-key
${ASADMIN} --passwordfile generated/secrets/apcm-service-hawkbit-file create-password-alias apcm-service-hawkbit-password

# Pour Frontend
${ASADMIN} --passwordfile generated/secrets/apcm-mongo-cms-file create-password-alias apcm-mongo-cms-password
${ASADMIN} --passwordfile generated/secrets/apcm-mongo-hmi-file create-password-alias apcm-mongo-hmi-password
```

**12. Configuration des logs**
```bash
${ASADMIN} set-log-attributes --target=server-config ...
```

**13. Arrêt de Payara**
```bash
source ./stopDomain.sh
```

**14. Installation du service (Linux)**
```bash
chown -R root:root $PAYARA_HOME
chmod -R 750 $PAYARA_HOME

# Nettoyage des anciens init scripts
rm -f /etc/init.d/payara_ampacimon-domain

# Création du service systemd
${ASADMIN} create-service --domaindir $PAYARA_HOME/glassfish/domains --nodedir $DOMAIN_NAME --node $DOMAIN_NAME

# Copie de la configuration CPU affinity
mkdir -p /etc/systemd/system/payara_ampacimon-domain.service.d
cp generated/services/overrides.conf /etc/systemd/system/payara_ampacimon-domain.service.d/override.conf

# Recharge et démarrage
systemctl daemon-reload
systemctl enable payara_ampacimon-domain
systemctl start payara_ampacimon-domain
```

**15. Installation du service (Windows)**
```bash
# Appelle PowerShell avec élévation de privilèges
powershell.exe -executionpolicy bypass -Command "Start-Process ... _setup-service.ps1 -verb runas -wait"
```

**16. Post-vérifications**
```bash
source ./generated/bash-scripts/_setup-postcheck.sh
```

#### **Variables Utilisées**

```bash
# Répertoires
currentdir=$(pwd)
PAYARA_HOME="payara5"
DOMAIN_NAME="ampacimon-domain"
ASADMIN=${PAYARA_HOME}/bin/asadmin
ADMIN_PASSWORD="admin"

# Type de déploiement
opt="Frontend" | "Backend" | "SingleInstance"

# Ports (dépendent du type)
ADMIN_PORT=...      # @front.admin.port@ ou @server.admin.port@
HTTP_PORT=...       # @front.http.port@ ou @server.http.port@
HTTPS_PORT=...      # @front.https.port@ ou @server.https.port@
JAVA_PORT=...       # @front.java.debugger.port@ ou @server.java.debugger.port@
JMX_PORT=...        # @front.jmx.port@ ou @server.jmx.port@
JMS_PORT=...        # @front.jms.port@ ou @server.jms.port@
ORB_HTTP_PORT=...   # @front.orb.listener.port@ ou @server.orb.listener.port@
ORB_AUTH_PORT=...   # @front.orb.mutualauth.port@ ou @server.orb.mutualauth.port@
ORB_HTTPS_PORT=...  # @front.orb.ssl.port@ ou @server.orb.ssl.port@
HAZEL_PORT=...      # @front.hazelcast.port@ ou @server.hazelcast.port@
HAZEL_START_PORT=... # @front.hazelcast.start.port@ ou @server.hazelcast.start.port@
SHELL_PORT=...      # @front.shell.telnet.port@ ou @server.shell.telnet.port@

SERVICES_URL=...    # @front.services.url@ ou @server.services.url@
SERVICES_URL_RMI=... # Identique à SERVICES_URL
MAIL_CONFIG=...     # generated/config/front-mail.xml ou server-mail.xml
```

#### **Problèmes Identifiés**

| **Problème** | **Impact** | **Solution Ansible** |
|-------------|-----------|----------------------|
| **Sélection interactive** | Bloque l'automatisation | Utiliser une variable `payara_type` |
| **Confirmation utilisateur** | Bloque l'automatisation | Supprimer ou utiliser `--force` |
| **asadmin interactif** | Requiert input manuel | Utiliser des fichiers de password |
| **Build complexe** | Difficile à reproduire | Modules Ansible dédiés |
| **Paths hardcodés** | Pas flexible | Variables Ansible |
| **Nombreux ports** | Configuration complexe | Structurer les variables |
| **Différences Frontend/Backend** | Logique conditionnelle | Tâches conditionnelles Ansible |

#### **Solution Ansible Complète**

```yaml
# roles/payara/tasks/setup.yml

# ============================================================
# Étape 0 : Définir le type de déploiement
# ============================================================

- name: Set deployment type
  ansible.builtin.set_fact:
    payara_deployment_type: "{{ payara_type | default('SingleInstance') }}"
  tags: [payara, setup]

- name: Validate deployment type
  ansible.builtin.assert:
    that: payara_deployment_type in ['Frontend', 'Backend', 'SingleInstance']
    msg: "payara_type must be Frontend, Backend, or SingleInstance"
  tags: [payara, setup]

# ============================================================
# Étape 1 : Initialisation
# ============================================================

- name: Set Payara variables based on deployment type
  ansible.builtin.set_fact:
    payara_vars: >
      {% if payara_deployment_type in ['Frontend', 'SingleInstance'] %}
      {{"admin_port": "{{ front_admin_port | default(4848) }}",
        "http_port": "{{ front_http_port | default(8080) }}",
        "https_port": "{{ front_https_port | default(8181) }}",
        "java_port": "{{ front_java_debugger_port | default(9009) }}",
        "jmx_port": "{{ front_jmx_port | default(8686) }}",
        "jms_port": "{{ front_jms_port | default(7676) }}",
        "orb_http_port": "{{ front_orb_listener_port | default(3700) }}",
        "orb_auth_port": "{{ front_orb_mutualauth_port | default(3820) }}",
        "orb_https_port": "{{ front_orb_ssl_port | default(3920) }}",
        "hazel_port": "{{ front_hazelcast_port | default(5900) }}",
        "hazel_start_port": "{{ front_hazelcast_start_port | default(4900) }}",
        "shell_port": "{{ front_shell_telnet_port | default(6666) }}",
        "services_url": "{{ front_services_url | default('localhost') }}",
        "mail_config": "front-mail.xml"}}
      {% elif payara_deployment_type == 'Backend' %}
      {{"admin_port": "{{ server_admin_port | default(4848) }}",
        "http_port": "{{ server_http_port | default(8080) }}",
        "https_port": "{{ server_https_port | default(8181) }}",
        "java_port": "{{ server_java_debugger_port | default(9009) }}",
        "jmx_port": "{{ server_jmx_port | default(8686) }}",
        "jms_port": "{{ server_jms_port | default(7676) }}",
        "orb_http_port": "{{ server_orb_listener_port | default(3700) }}",
        "orb_auth_port": "{{ server_orb_mutualauth_port | default(3820) }}",
        "orb_https_port": "{{ server_orb_ssl_port | default(3920) }}",
        "hazel_port": "{{ server_hazelcast_port | default(5900) }}",
        "hazel_start_port": "{{ server_hazelcast_start_port | default(4900) }}",
        "shell_port": "{{ server_shell_telnet_port | default(6666) }}",
        "services_url": "{{ server_services_url | default('localhost') }}",
        "mail_config": "server-mail.xml"}}
      {% endif %}
  tags: [payara, setup]

- name: Create bundle log directory
  ansible.builtin.file:
    path: "{{ playbook_dir }}/bundle_log"
    state: directory
    mode: '0755'
  tags: [payara, setup]

# ============================================================
# Étape 2 : Pré-vérifications
# ============================================================

- name: Include precheck tasks
  ansible.builtin.include_tasks: precheck.yml
  tags: [payara, setup]

# ============================================================
# Étape 3 : Arrêt et suppression du domaine existant
# ============================================================

- name: Stop existing domain
  community.general.asadmin:
    name: stop-domain
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
  ignore_errors: yes
  register: stop_result
  tags: [payara, domain]

- name: Delete existing domain
  community.general.asadmin:
    name: delete-domain
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
  ignore_errors: yes
  register: delete_result
  tags: [payara, domain]

- name: Remove existing service
  ansible.builtin.include_tasks: remove_service.yml
  tags: [payara, service]

# ============================================================
# Étape 4 : Création du domaine
# ============================================================

- name: Create Payara domain
  community.general.asadmin:
    name: create-domain
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
    options: >
      --domainproperties 
      domain.instancePort={{ payara_vars.http_port }}:
      http.ssl.port={{ payara_vars.https_port }}:
      java.debugger.port={{ payara_vars.java_port }}:
      domain.jmxPort={{ payara_vars.jmx_port }}:
      jms.port={{ payara_vars.jms_port }}:
      orb.listener.port={{ payara_vars.orb_http_port }}:
      orb.mutualauth.port={{ payara_vars.orb_auth_port }}:
      orb.ssl.port={{ payara_vars.orb_https_port }}:
      hazelcast.das.port={{ payara_vars.hazel_port }}:
      hazelcast.start.port={{ payara_vars.hazel_start_port }}:
      osgi.shell.telnet.port={{ payara_vars.shell_port }}
      --template {{ payara_home }}/glassfish/common/templates/gf/production-domain.jar
      --user admin --nopassword
      --keytooloptions CN={{ payara_vars.services_url }}
      {{ payara_domain_name | default('ampacimon-domain') }}
  register: create_domain
  until: create_domain is succeeded
  retries: 3
  delay: 10
  tags: [payara, domain]

# ============================================================
# Étape 5 : Démarrage du domaine
# ============================================================

- name: Start Payara domain
  community.general.asadmin:
    name: start-domain
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
  register: start_domain
  until: start_domain is succeeded
  retries: 5
  delay: 10
  tags: [payara, domain]

# ============================================================
# Étape 6 : Configuration de base (asadmin-common.txt)
# ============================================================

- name: Apply common asadmin commands
  community.general.asadmin:
    name: multimode
    file: "{{ payara_extract_path }}/resources/bash-scripts/asadmin-common.txt"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  register: common_config
  until: common_config is succeeded
  retries: 3
  delay: 5
  tags: [payara, config]

# ============================================================
# Étape 7 : Copie des fichiers
# ============================================================

- name: Copy AmpacimonAuditModule
  ansible.builtin.copy:
    src: "{{ payara_extract_path }}/classes/"
    dest: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/lib/"
    remote_src: yes
  tags: [payara, config]

- name: Deploy logback.xml
  ansible.builtin.template:
    src: config/logback.xml.j2
    dest: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/config/logback.xml"
    mode: '0644'
  tags: [payara, config]

- name: Deploy favicon and clean docroot
  ansible.builtin.copy:
    src: "{{ payara_extract_path }}/resources/favicon.ico"
    dest: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/docroot/favicon.ico"
    remote_src: yes
  tags: [payara, config]

- name: Clean docroot (remove unnecessary files)
  ansible.builtin.file:
    path: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/docroot/{{ item }}"
    state: absent
  loop:
    - js
    - fonts
    - img
    - css
  tags: [payara, config]

# ============================================================
# Étape 8 : Configuration Mail
# ============================================================

- name: Deploy mail configuration
  ansible.builtin.template:
    src: "config/{{ payara_vars.mail_config }}.j2"
    dest: "/tmp/{{ payara_vars.mail_config }}"
    mode: '0644'
  tags: [payara, config]

- name: Add mail resources
  community.general.asadmin:
    name: add-resources
    file: "/tmp/{{ payara_vars.mail_config }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  tags: [payara, config]

- name: Disable mail debug
  community.general.asadmin:
    name: set
    options: resources.mail-resource.mail/sender.debug=false
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  tags: [payara, config]

# ============================================================
# Étape 9 : Configuration RMI
# ============================================================

- name: Set RMI server hostname
  community.general.asadmin:
    name: create-jvm-options
    options: "-Djava.rmi.server.hostname={{ payara_vars.services_url }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  tags: [payara, config]

# ============================================================
# Étape 10 : Configuration spécifique par type
# ============================================================

- name: Include server-specific configuration (Backend/SingleInstance)
  ansible.builtin.include_tasks: setup_server.yml
  when: payara_deployment_type in ['Backend', 'SingleInstance']
  tags: [payara, config]

- name: Include frontend-specific configuration (Frontend/SingleInstance)
  ansible.builtin.include_tasks: setup_front.yml
  when: payara_deployment_type in ['Frontend', 'SingleInstance']
  tags: [payara, config]

# ============================================================
# Étape 11 : Configuration Admin
# ============================================================

- name: Change admin password
  community.general.asadmin:
    name: change-admin-password
    user: admin
    passwordfile: "/tmp/change_admin_password.txt"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  vars:
    admin_password_file: >
      AS_ADMIN_PASSWORD=
      AS_ADMIN_NEWPASSWORD={{ payara_admin_password | default('admin') }}
  tags: [payara, admin]

- name: Enable secure admin
  community.general.asadmin:
    name: enable-secure-admin
    passwordfile: "/tmp/admin_password.txt"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  vars:
    password_file: "AS_ADMIN_PASSWORD={{ payara_admin_password | default('admin') }}"
  tags: [payara, admin]

# ============================================================
# Étape 12 : Création des aliases de mots de passe
# ============================================================

- name: Create password aliases
  community.general.asadmin:
    name: create-password-alias
    passwordfile: "{{ payara_extract_path }}/generated/secrets/{{ item }}-file"
    alias: "{{ item }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  loop: >
    {% if payara_deployment_type in ['Backend', 'SingleInstance'] %}
    {{ ['apcm-service-phoenix', 'apcm-mail', 'apcm-mongo-pho', 'apcm-mongo-adg', 'apcm-dbpool', 'apcm-service-twc', 'apcm-service-cloudloop', 'apcm-service-hawkbit'] }}
    {% elif payara_deployment_type == 'Frontend' %}
    {{ ['apcm-mongo-cms', 'apcm-mongo-hmi'] }}
    {% else %}
    {{ ['apcm-service-phoenix', 'apcm-mail', 'apcm-mongo-pho', 'apcm-mongo-adg', 'apcm-dbpool', 'apcm-service-twc', 'apcm-service-cloudloop', 'apcm-service-hawkbit', 'apcm-mongo-cms', 'apcm-mongo-hmi'] }}
    {% endif %}
  tags: [payara, secrets]

# ============================================================
# Étape 13 : Configuration des logs
# ============================================================

- name: Configure server logs
  community.general.asadmin:
    name: set-log-attributes
    options: >
      --target=server-config 
      handlers='java.util.logging.ConsoleHandler':
      handlerServices='com.sun.enterprise.server.logging.GFFileHandler,com.sun.enterprise.server.logging.SyslogHandler':
      ... (toutes les options)
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    admin_port: "{{ payara_vars.admin_port }}"
  tags: [payara, config]

# ============================================================
# Étape 14 : Arrêt du domaine
# ============================================================

- name: Stop Payara domain
  community.general.asadmin:
    name: stop-domain
    domain: "{{ payara_domain_name | default('ampacimon-domain') }}"
    asadmin: "{{ payara_home }}/bin/asadmin"
    admin_port: "{{ payara_vars.admin_port }}"
  register: stop_payara
  until: stop_payara is succeeded
  retries: 5
  delay: 10
  tags: [payara, domain]

# ============================================================
# Étape 15 : Installation du service
# ============================================================

- name: Include service setup tasks
  ansible.builtin.include_tasks: setup_service.yml
  tags: [payara, service]

# ============================================================
# Étape 16 : Post-vérifications
# ============================================================

- name: Include postcheck tasks
  ansible.builtin.include_tasks: postcheck.yml
  tags: [payara, setup]
```

**Note** : Le module `community.general.asadmin` est nécessaire pour interagir avec Payara.

---

### 3️⃣ `2-payara--deploy-front-cron.sh` et `2-payara--deploy-backend-cron.sh`

**Code Source** :
```bash
# deploy-front-cron.sh
source ./generated/bash-scripts/_create-front-cronjobs.sh

# deploy-backend-cron.sh
source ./generated/bash-scripts/_create-server-cronjobs.sh
```

**Solution Ansible** : Adapter les solutions NGINX/Keycloak pour Payara.

---

### 4️⃣ `_setup-variables.sh` (Définition des Variables)

**Code Source** :
```bash
if [[ "$opt" == "Frontend" || "$opt" == "SingleInstance" ]]; then
    ADMIN_PORT=@front.admin.port@
    HTTP_PORT=@front.http.port@
    HTTPS_PORT=@front.https.port@
    # ... (toutes les autres variables frontend)
    MAIL_CONFIG=generated/config/front-mail.xml
elif [[ "$opt" == "Backend" ]]; then
    ADMIN_PORT=@server.admin.port@
    HTTP_PORT=@server.http.port@
    HTTPS_PORT=@server.https.port@
    # ... (toutes les autres variables backend)
    MAIL_CONFIG=generated/config/server-mail.xml
fi
```

**Solution Ansible** : Déjà géré dans `setup.yml` avec `payara_vars`.

---

### 5️⃣ `_setup-precheck.sh` (Pré-vérifications)

**Fonctionnalités** :
- Vérification de la résolution DNS des hôtes
- Vérification des ports accessibles
- Vérification de l'accès aux services externes (Keycloak, TWC, CloudLoop, Hawkbit)
- Vérification de l'authentification MongoDB

**Solution Ansible** :

```yaml
# roles/payara/tasks/precheck.yml

- name: Test DNS resolution for server.services.url
  ansible.builtin.getent:
    database: hosts
    key: "{{ server_services_url }}"
  register: server_dns
  ignore_errors: yes
  tags: [payara, precheck]

- name: Fail if server.services.url cannot be resolved
  ansible.builtin.fail:
    msg: "Host {{ server_services_url }} could not be resolved"
  when: server_dns.failed
  tags: [payara, precheck]

- name: Test DNS resolution for front.services.url
  ansible.builtin.getent:
    database: hosts
    key: "{{ front_services_url }}"
  register: front_dns
  ignore_errors: yes
  tags: [payara, precheck]

- name: Fail if front.services.url cannot be resolved
  ansible.builtin.fail:
    msg: "Host {{ front_services_url }} could not be resolved"
  when: front_dns.failed
  tags: [payara, precheck]

- name: Test port accessibility
  ansible.builtin.wait_for:
    host: "{{ item.host }}"
    port: "{{ item.port }}"
    timeout: 10
  loop: >
    {% if payara_deployment_type in ['Frontend', 'SingleInstance'] %}
    {{ [{'host': front_services_url, 'port': front_https_port | default(8181)}] }}
    {% elif payara_deployment_type == 'Backend' %}
    {{ [{'host': server_services_url, 'port': server_https_port | default(8181)}] }}
    {% endif %}
  ignore_errors: yes
  tags: [payara, precheck]

# ... autres vérifications
```

---

### 6️⃣ `_setup-remove-service.sh` (Suppression du Service)

**Solution Ansible** : Voir solution NGINX/Keycloak adaptée pour Payara.

---

### 7️⃣ `_setup-server.sh` et `_setup-front.sh` (Configurations Spécifiques)

Ces scripts contiennent la **configuration spécifique** pour Backend et Frontend.

**`_setup-server.sh`** (Backend) :
- Configuration des pools de connexion (MongoDB, PostgreSQL)
- Configuration des datasources
- Configuration des services backend

**`_setup-front.sh`** (Frontend) :
- Configuration des services frontend
- Configuration des applications web

**Solution Ansible** : Convertir ces scripts en tâches Ansible utilisant le module `community.general.asadmin`.

---

### 8️⃣ `_create-front-cronjobs.sh` et `_create-server-cronjobs.sh`

**Solution Ansible** : Adapter les solutions NGINX/Keycloak pour Payara.

---

### 9️⃣ Scripts d'initialisation des bases de données (`mongo/latest/*.js`, `sql/latest/*.sql`)

#### **Fonctionnalités**

| Type | Script | Détails |
|------|--------|---------|
| **MongoDB** | `resources/mongo/latest/1-create-default-collection.js` | Crée la collection par défaut (`apcm-phoenix-default`) |
| **MongoDB** | `resources/mongo/latest/2-create-users-roles.js` | Crée les users et rôles (pho, adg, cms, hmi) |
| **PostgreSQL** | `resources/sql/latest/postgresql/1-create-database-20260529.sql` | Crée bases, users et grants PostgreSQL |
| **SQLServer** | `resources/sql/latest/sqlserver/1-create-database-20260529-ms.sql` | Variante MS-SQL du même script |

Ces scripts sont filtrés par Ant (tokens de connexion `@...@`), puis exécutés manuellement après l'installation des bases. Ils sont consommés par les pools de connexion configurés dans Payara (`apcm-mongo-*`, `apcm-dbpool`).

#### **Problèmes**

| Problème | Impact | Solution Ansible |
|----------|--------|------------------|
| **Exécution manuelle** | Étape oubliable, non reproductible | Tâches idempotentes `init_databases.yml` |
| **Secrets en clair** | Mots de passe DB filtrés dans `generated/` | Variables Vault + `no_log: true` |
| **Pas de conditionnement** | Réexécutés à chaque run ou jamais | Modules idempotents (create if missing) |
| **RDS non couvert** | Le rôle `postgresql` actuel ne crée les bases que pour RDS | Étendre/généraliser la création de bases |

#### **Solution Ansible**

```yaml
# roles/payara/tasks/init_databases.yml
# À exécuter après l'installation des bases (rôles mongodb/postgresql)
# et AVANT le setup Payara (pools de connexion)

# ============================================================
# 1. MongoDB : collection par défaut + users/rôles
# ============================================================

- name: Run MongoDB init scripts
  community.mongodb.mongodb_shell:
    login_host: "{{ mongodb_host }}"
    login_port: "{{ mongodb_port }}"
    login_database: "{{ mongo_database_name }}"
    login_user: "{{ mongodb_admin_user | default(omit) }}"
    login_password: "{{ mongodb_admin_password | default(omit) }}"
    evalfile: "{{ payara_extract_path }}/generated/resources/mongo/latest/{{ item }}"
  loop:
    - 1-create-default-collection.js
    - 2-create-users-roles.js
  no_log: true
  when: ansible_facts['os_family'] != 'Windows'
  tags: [payara, database, mongo]

# Alternative : créer les users via le module dédié (plus idempotent)
- name: Ensure MongoDB application users exist
  community.mongodb.mongodb_user:
    login_host: "{{ mongodb_host }}"
    login_port: "{{ mongodb_port }}"
    login_user: "{{ mongodb_admin_user | default(omit) }}"
    login_password: "{{ mongodb_admin_password | default(omit) }}"
    database: "{{ mongo_database_name }}"
    name: "{{ item.name }}"
    password: "{{ item.password }}"
    roles: "{{ item.roles }}"
    state: present
  loop:
    - name: apcm-pho
      password: "{{ vault_mongo_pho_password }}"
      roles: readWrite
    - name: apcm-adg
      password: "{{ vault_mongo_adg_password }}"
      roles: readWrite
    - name: apcm-cms
      password: "{{ vault_mongo_cms_password }}"
      roles: readWrite
    - name: apcm-hmi
      password: "{{ vault_mongo_hmi_password }}"
      roles: readWrite
  no_log: true
  when: ansible_facts['os_family'] != 'Windows'
  tags: [payara, database, mongo]

# ============================================================
# 2. PostgreSQL : exécution du script de création (hors RDS)
# ============================================================

- name: Run PostgreSQL init script (local)
  community.postgresql.postgresql_script:
    login_host: "{{ postgresql_host }}"
    login_port: "{{ postgresql_port | default(5432) }}"
    login_user: "{{ postgresql_admin_user }}"
    login_password: "{{ vault_postgresql_admin_password }}"
    path: "{{ payara_extract_path }}/generated/resources/sql/latest/postgresql/1-create-database-20260529.sql"
  no_log: true
  when:
    - not (postgresql_rds_enabled | default(false))
    - ansible_facts['os_family'] != 'Windows'
  tags: [payara, database, postgres]

# Note RDS : si `postgresql_rds_enabled: true`, la création des bases/users/grants
# est couverte par `roles/postgresql/tasks/config_rds.yml` (playbook config_databases.yml)
# — ne pas réexécuter le script SQL. Exception : le superadmin n'est jamais créé sur RDS.

# ============================================================
# 3. SQLServer (si backend MS-SQL requis)
# ============================================================

- name: Run SQLServer init script
  ansible.builtin.command:
    cmd: >-
      sqlcmd -S {{ mssql_host }} -U {{ mssql_admin_user }} -P {{ vault_mssql_admin_password }}
      -i {{ payara_extract_path }}/generated/resources/sql/latest/sqlserver/1-create-database-20260529-ms.sql
  no_log: true
  when: mssql_enabled | default(false)
  tags: [payara, database, mssql]
```

**Dépendances** :
```bash
ansible-galaxy collection install community.mongodb community.postgresql
```

**Ordre d'exécution dans `tasks/main.yml`** :
`init_databases.yml` **avant** le setup Payara (`setup_server.yml`/`setup_front.yml`), car les pools de connexion (`apcm-mongo-*`, `apcm-dbpool`) échouent au ping si les bases/users n'existent pas.

**Variables à définir** (Vault) :
```yaml
# group_vars/all_secrets.yml
vault_mongo_pho_password: "..."
vault_mongo_adg_password: "..."
vault_mongo_cms_password: "..."
vault_mongo_hmi_password: "..."
vault_postgresql_admin_password: "..."
vault_mssql_admin_password: "..."
```

---

## 🎯 Solutions Complètes par Type de Déploiement

### Structure Recommandée

```
roles/payara/
├── defaults/
│   └── main.yml              # Variables par défaut
├── files/
│   └── scripts/              # Scripts statiques à copier
├── templates/
│   ├── config/               # Templates de configuration
│   │   ├── logback.xml.j2
│   │   ├── front-mail.xml.j2
│   │   ├── server-mail.xml.j2
│   │   └── ...
│   └── bash-scripts/         # Templates pour les scripts générés
│       └── asadmin-common.txt.j2
└── tasks/
    ├── main.yml
    ├── setup.yml              # Setup principal
    ├── setup_server.yml       # Configuration Backend
    ├── setup_front.yml        # Configuration Frontend
    ├── setup_service.yml      # Installation du service
    ├── setup_service_linux.yml
    ├── setup_service_windows.yml
    ├── remove_service.yml
    ├── precheck.yml           # Pré-vérifications
    ├── postcheck.yml          # Post-vérifications
    ├── deploy_front_cron.yml  # Tâches cron Frontend
    ├── deploy_backend_cron.yml # Tâches cron Backend
    └── ...
```

---

## 📊 Mapping des Variables Payara

### Variables Globales

```yaml
# group_vars/all.yml

# ============================================================
# Payara - Base Configuration
# ============================================================
payara_home: "/opt/adr/payara5"
payara_domain_name: "ampacimon-domain"
payara_admin_password: "{{ vault_payara_admin_password }}"
payara_type: "SingleInstance"  # Frontend, Backend, SingleInstance

# ============================================================
# Payara - Common Ports (applicable to all types)
# ============================================================
# Ces ports sont utilisés dans les templates

# ============================================================
# Payara - Frontend Specific
# ============================================================
front_admin_port: 4848
front_http_port: 8080
front_https_port: 8181
front_java_debugger_port: 9009
front_jmx_port: 8686
front_jms_port: 7676
front_orb_listener_port: 3700
front_orb_mutualauth_port: 3820
front_orb_ssl_port: 3920
front_hazelcast_port: 5900
front_hazelcast_start_port: 4900
front_shell_telnet_port: 6666
front_services_url: "{{ domain }}"

# ============================================================
# Payara - Backend Specific
# ============================================================
server_admin_port: 4848
server_http_port: 8080
server_https_port: 8181
server_java_debugger_port: 9009
server_jmx_port: 8686
server_jms_port: 7676
server_orb_listener_port: 3700
server_orb_mutualauth_port: 3820
server_orb_ssl_port: 3920
server_hazelcast_port: 5900
server_hazelcast_start_port: 4900
server_shell_telnet_port: 6666
server_services_url: "{{ domain }}"
```

### Variables de Connexion

```yaml
# ============================================================
# Payara - Service URLs
# ============================================================
keycloak_url: "https://{{ keycloak_host_fqdn }}:{{ keycloak_listen_https_port }}/auth"
keycloak_realm: "apcm-realm"
keycloak_client_id: "{{ keycloak_prefix }}-adr"

# Services externes
twc_enabled: false
twc_url: "https://twc.example.com"
cloudloop_enabled: false
cloudloop_url: "https://cloudloop.example.com"
hawkbit_enabled: false
hawkbit_url: "https://hawkbit.example.com"

# ============================================================
# Payara - Database Configuration
# ============================================================

# MongoDB
mongo_url: "mongodb://{{ mongodb_host }}:{{ mongodb_port }}/"
mongo_database_name: "apcm-phoenix-default"
mongo_auth: true
mongo_tls: true
mongo_tls_enable_certschecks: false

# MongoDB Users
mongo_pho_password: "{{ vault_mongo_pho_password }}"
mongo_adg_password: "{{ vault_mongo_adg_password }}"
mongo_hmi_password: "{{ vault_mongo_hmi_password }}"
mongo_cms_password: "{{ vault_mongo_cms_password }}"

# PostgreSQL
postgresql_host: "localhost"
postgresql_port: 5432
postgresql_db_name: "apcm_db"
postgresql_user: "apcm_user"
postgresql_password: "{{ vault_postgresql_password }}"

# ============================================================
# Payara - Data Directories
# ============================================================
phoenix_datadir: "/opt/adr/data"
phoenix_datadir_user: ""
phoenix_datadir_password: ""
```

---

## 📝 Checklist de Migration Payara

### ✅ À Faire

- [ ] **Préparation**
  - [ ] Créer la structure `roles/payara/`
  - [ ] Installer la collection `community.general` pour le module `asadmin`

- [ ] **Templates**
  - [ ] Convertir tous les fichiers de `resources/` en templates Jinja2
  - [ ] Identifier et documenter tous les tokens `@...@`
  - [ ] Créer des templates pour les fichiers de configuration

- [ ] **Tâches Ansible**
  - [ ] `tasks/setup.yml` (remplace `1-payara--setup.sh`)
  - [ ] `tasks/setup_server.yml` (remplace `_setup-server.sh`)
  - [ ] `tasks/setup_front.yml` (remplace `_setup-front.sh`)
  - [ ] `tasks/setup_service.yml`
  - [ ] `tasks/remove_service.yml`
  - [ ] `tasks/precheck.yml`
  - [ ] `tasks/postcheck.yml`
  - [ ] `tasks/deploy_front_cron.yml`
  - [ ] `tasks/deploy_backend_cron.yml`
  - [ ] `tasks/init_databases.yml` (remplace l'exécution manuelle de `mongo/latest/*.js` et `sql/latest/**/*.sql`)
    - [ ] MongoDB : collection par défaut + users (pho, adg, cms, hmi)
    - [ ] PostgreSQL : script `1-create-database-*.sql` (hors RDS ; provisioning users/dbs déjà migré vers `tasks/config*.yml`)
    - [ ] SQLServer : variante `-ms.sql` (si backend MS-SQL requis)

- [ ] **Variables**
  - [ ] Secrets d'initialisation DB dans `group_vars/all_secrets.yml` (Vault, `no_log: true`)
  - [ ] Définir toutes les variables dans `group_vars/all.yml`
  - [ ] Créer `group_vars/all_secrets.yml` (encrypted)
  - [ ] Définir les defaults dans `roles/payara/defaults/main.yml`
  - [ ] Créer des variables par type (Frontend, Backend, SingleInstance)

- [ ] **Tests**
  - [ ] Tester chaque type de déploiement
  - [ ] Tester avec PostgreSQL
  - [ ] Tester avec MongoDB
  - [ ] Tester l'initialisation MongoDB (collection + users) sur instance vide
  - [ ] Tester l'initialisation PostgreSQL (script SQL) et vérifier le non-double-exécution avec `config_rds.yml`
  - [ ] Tester le clustering
  - [ ] Vérifier l'intégration avec Keycloak

- [ ] **Nettoyage**
  - [ ] Supprimer les références aux scripts
  - [ ] Mettre à jour la documentation

---

## 💡 Conseils Spécifiques Payara

### 1. **Utilisation du Module `community.general.asadmin`**

Ce module permet d'exécuter des commandes `asadmin` directement depuis Ansible.

**Installation** :
```bash
ansible-galaxy collection install community.general
```

**Exemple** :
```yaml
- name: Create domain
  community.general.asadmin:
    name: create-domain
    domain: mydomain
    admin_port: 4848
    asadmin: /opt/adr/payara5/bin/asadmin
    options: --user admin --passwordfile /tmp/password.txt
```

### 2. **Gestion des Différents Types de Déploiement**

**Approche recommandée** : Utiliser une variable `payara_type` et des conditions.

```yaml
- name: Include frontend-specific tasks
  ansible.builtin.include_tasks: setup_front.yml
  when: payara_type in ['Frontend', 'SingleInstance']

- name: Include backend-specific tasks
  ansible.builtin.include_tasks: setup_server.yml
  when: payara_type in ['Backend', 'SingleInstance']
```

### 3. **Gestion des Mots de Passe**

Les mots de passe sont nombreux dans Payara. **Utiliser Ansible Vault**.

**Exemple de fichier secrets** :
```yaml
# group_vars/all_secrets.yml (encrypted)
payara_admin_password: "MyS3cr3tP@ssw0rd"

# MongoDB
mongo_pho_password: "{{ vault_mongo_pho_password }}"
mongo_adg_password: "{{ vault_mongo_adg_password }}"
mongo_hmi_password: "{{ vault_mongo_hmi_password }}"
mongo_cms_password: "{{ vault_mongo_cms_password }}"

# PostgreSQL
postgresql_password: "{{ vault_postgresql_password }}"

# Services externes
apcm_service_twc_api_key: "{{ vault_twc_api_key }}"
apcm_service_cloudloop_api_key: "{{ vault_cloudloop_api_key }}"
apcm_service_hawkbit_password: "{{ vault_hawkbit_password }}"
```

### 4. **Gestion des Pools de Connexion**

**Exemple avec `community.general.asadmin`** :
```yaml
- name: Create JDBC connection pool
  community.general.asadmin:
    name: create-jdbc-connection-pool
    poolname: mypool
    datasourcename: myds
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name }}"
    admin_port: "{{ payara_vars.admin_port }}"

- name: Create JDBC resource
  community.general.asadmin:
    name: create-jdbc-resource
    poolname: mypool
    jndiname: jdbc/myds
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name }}"
    admin_port: "{{ payara_vars.admin_port }}"
```

### 5. **Gestion des Applications Web**

**Déploiement d'applications** :
```yaml
- name: Deploy WAR file
  community.general.asadmin:
    name: deploy
    path: /path/to/app.war
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name }}"
    admin_port: "{{ payara_vars.admin_port }}"
```

### 6. **Gestion du Clustering**

**Configuration Hazelcast** :
```yaml
- name: Set cluster configuration
  community.general.asadmin:
    name: set
    options: "configs.config.server-config.hazelcast-configuration.hazelcast.datetime-format=yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name }}"
    admin_port: "{{ payara_vars.admin_port }}"
```

---

## 🚀 Commandes Utiles

### Pour installer la collection community.general

```bash
ansible-galaxy collection install community.general
```

### Pour tester une commande asadmin manuellement

```bash
/opt/adr/payara5/bin/asadmin --host localhost --port 4848 list-domains
```

### Pour lister tous les tokens dans les fichiers Payara

```bash
find TMP-CONFIG/sources/payara -type f -name "*.xml" -o -name "*.txt" -o -name "*.sh" | \
  xargs grep -oh '@[a-zA-Z0-9._-]*@' | sort -u
```

### Pour tester le déploiement Payara

```bash
ansible-playbook deploy.yml --limit localhost --tags payara --extra-vars "payara_type=SingleInstance"
```

---

## 🔐 Intégration Ansible Vault - Gestion des Secrets

**IMPÉRATIF** : Tous les mots de passe, clés API, certificats et secrets Payara doivent être stockés dans **Ansible Vault** et jamais en clair.

Payara a le plus grand nombre de secrets parmi les trois composants (NGINX, Keycloak, Payara).

---

### 1. Architecture des Fichiers Vault

```
ansible/
├── group_vars/
│   ├── all.yml                    # Variables NON sensibles
│   ├── all_secrets.yml            # Secrets communs (CHIFFRÉ)
│   ├── dev_secrets.yml            # Secrets dev (CHIFFRÉ)
│   ├── staging_secrets.yml        # Secrets staging (CHIFFRÉ)
│   └── prod_secrets.yml           # Secrets prod (CHIFFRÉ)
└── host_vars/
    └── <hostname>_secrets.yml     # Secrets spécifiques hôte (CHIFFRÉ)
```

**Organisation recommandée pour Payara** :
- `group_vars/all_secrets.yml` : Secrets communs à tous les types de déploiement
- `group_vars/<env>_secrets.yml` : Secrets spécifiques à l'environnement (dev/staging/prod)
- `group_vars/payara_<type>_secrets.yml` : Secrets spécifiques au type (Frontend/Backend/SingleInstance)

---

### 2. Structure des Secrets pour Payara

#### **Fichier `group_vars/all_secrets.yml` (à chiffrer)**

```yaml
# ============================================================
# Payara - Admin Credentials (tous types)
# ============================================================
payara_admin_user: "{{ vault_payara_admin_user }}"
payara_admin_password: "{{ vault_payara_admin_password }}"

# ============================================================
# Payara - Certificate Alias
# ============================================================
payara_cert_alias: "{{ vault_payara_cert_alias }}"

# ============================================================
# Payara - Master Password (pour les stores)
# ============================================================
payara_master_password: "{{ vault_payara_master_password }}"
```

#### **Fichier `group_vars/prod_secrets.yml` (exemple production)**

```yaml
# ============================================================
# Payara - Production Admin
# ============================================================
vault_payara_admin_user: "admin"
vault_payara_admin_password: "{{ random_password_32_chars }}"

# ============================================================
# Payara - Production Certificate
# ============================================================
vault_payara_cert_alias: "payara-prod-cert"

# ============================================================
# Payara - Production Master Password
# ============================================================
vault_payara_master_password: "{{ random_password_16_chars }}"

# ============================================================
# Payara - Database Credentials
# ============================================================

# MongoDB (pour tous les types)
mongo_pho_password: "{{ random_password_32_chars }}"
mongo_adg_password: "{{ random_password_32_chars }}"
mongo_hmi_password: "{{ random_password_32_chars }}"
mongo_cms_password: "{{ random_password_32_chars }}"

# PostgreSQL (Backend/SingleInstance)
postgresql_user: "payara_prod"
postgresql_password: "{{ random_password_32_chars }}"
postgresql_host: "prod-db.example.com"
postgresql_port: "5432"
postgresql_dbname: "payara_prod"

# ============================================================
# Payara - Services Externes API Keys
# ============================================================
apcm_service_twc_api_key: "{{ random_api_key_64_chars }}"
apcm_service_cloudloop_api_key: "{{ random_api_key_64_chars }}"
apcm_service_hawkbit_password: "{{ random_password_32_chars }}"

# ============================================================
# Payara - Mail Configuration
# ============================================================
payara_mail_host: "smtp.prod.example.com"
payara_mail_port: "587"
payara_mail_user: "payara@prod.example.com"
payara_mail_password: "{{ random_password_32_chars }}"
payara_mail_from: "payara@prod.example.com"

# ============================================================
# Payara - Type-Specific Configuration
# ============================================================
payara_type: "Backend"  # Frontend, Backend, ou SingleInstance
```

#### **Fichier `group_vars/payara_frontend_secrets.yml` (spécifique Frontend)**

```yaml
# ============================================================
# Payara Frontend - Specific Database
# ============================================================
vault_payara_frontend_db_host: "frontend-db.example.com"
vault_payara_frontend_db_port: "5432"
vault_payara_frontend_db_user: "frontend_user"
vault_payara_frontend_db_password: "{{ random_password_32_chars }}"

# ============================================================
# Payara Frontend - Hazelcast Cluster
# ============================================================
payara_cluster_password: "{{ random_password_32_chars }}"
payara_hazelcast_password: "{{ random_password_32_chars }}"
```

---

### 3. Commandes de Chiffrement/Déchiffrement

#### **Créer et gérer les fichiers Vault**

```bash
# Créer un nouveau fichier Vault
ansible-vault create group_vars/prod_secrets.yml

# Éditer un fichier existant
ansible-vault edit group_vars/prod_secrets.yml

# Chiffrer un fichier existant
ansible-vault encrypt group_vars/all_secrets.yml

# Déchiffrer pour vérification (attention!)
ansible-vault view group_vars/prod_secrets.yml

# Déchiffrer temporairement pour éditer
ansible-vault edit group_vars/prod_secrets.yml
```

#### **Changer le mot de passe du Vault**

```bash
ansible-vault rekey group_vars/prod_secrets.yml
```

---

### 4. Intégration avec les Playbooks

#### **Exécution avec Vault**

```bash
# Avec demande interactive
ansible-playbook payara-deploy.yml --ask-vault-pass --extra-vars "payara_type=Backend"

# Avec fichier de mot de passe
ansible-playbook payara-deploy.yml --vault-password-file ~/.vault_pass.txt --extra-vars "payara_type=SingleInstance"

# Avec variable d'environnement
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass.txt
ansible-playbook payara-deploy.yml --extra-vars "payara_type=Frontend"
```

#### **Exemple de playbook Payara avec Vault**

```yaml
---
- name: Deploy Payara Configuration
  hosts: payara_servers
  vars:
    payara_type: "{{ payara_type | default('SingleInstance') }}"
  vars_files:
    - group_vars/all.yml
    - group_vars/all_secrets.yml
    - "group_vars/{{ environment }}_secrets.yml"
    - "group_vars/payara_{{ payara_type | lower }}_secrets.yml"
  
  tasks:
    - name: Include type-specific variables
      ansible.builtin.include_vars:
        file: "vars/payara_{{ payara_type | lower }}.yml"
      no_log: true
      
    - name: Create Payara domain directory
      ansible.builtin.file:
        path: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}"
        state: directory
        owner: payara
        group: payara
        mode: '0750'
      
    - name: Deploy asadmin password file
      ansible.builtin.template:
        src: templates/password.txt.j2
        dest: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/password.txt"
        owner: payara
        group: payara
        mode: '0600'  # Uniquement le propriétaire
      no_log: true
      
    - name: Deploy domain.xml
      ansible.builtin.template:
        src: templates/domain.xml.j2
        dest: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/config/domain.xml"
        owner: payara
        group: payara
        mode: '0640'
      no_log: true
```

---

### 5. Bonnes Pratiques de Sécurité

#### **Permissions des fichiers**

```yaml
# TOUJOURS définir des permissions strictes
- name: Deploy admin password file
  ansible.builtin.template:
    src: templates/admin-password.txt.j2
    dest: "{{ payara_vars.admin_password_file }}"
    owner: payara
    group: payara
    mode: '0600'  # Lecteur/écriture uniquement pour le propriétaire
  no_log: true

- name: Deploy configuration files
  ansible.builtin.template:
    src: "templates/{{ item }}.j2"
    dest: "{{ payara_home }}/glassfish/domains/{{ payara_domain_name }}/config/{{ item }}"
    owner: payara
    group: payara
    mode: '0640'  # Propriétaire r/w, groupe r
  loop:
    - domain.xml
    - server-configs/server-config.xml
  no_log: true
```

#### **Gestion des secrets dans les templates**

```yaml
# MAUVAIS - hardcoded dans le template
# <master-password>mysecretpassword</master-password>

# BON - utiliser des variables
<master-password>{{ payara_master_password }}</master-password>

# Dans le playbook:
payara_master_password: "{{ vault_payara_master_password }}"
```

#### **Protéger les commandes asadmin**

```yaml
- name: Create JDBC connection pool
  community.general.asadmin:
    name: create-jdbc-connection-pool
    poolname: mypool
    datasourcename: myds
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name }}"
    admin_port: "{{ payara_vars.admin_port }}"
    admin_user: "{{ payara_admin_user }}"
    admin_password: "{{ payara_admin_password }}"
  no_log: true  # Important pour cacher les credentials
  
- name: Create JDBC resource
  community.general.asadmin:
    name: create-jdbc-resource
    poolname: mypool
    jndiname: jdbc/myds
    asadmin: "{{ payara_home }}/bin/asadmin"
    domain: "{{ payara_domain_name }}"
    admin_port: "{{ payara_vars.admin_port }}"
    admin_user: "{{ payara_admin_user }}"
    admin_password: "{{ payara_admin_password }}"
  no_log: true
```

---

### 6. Génération de Mots de Passe Aléatoires

#### **Utiliser le module Ansible**

```yaml
- name: Generate passwords for all Payara components
  community.general.random_string:
    length: 32
    special: true
    upper: true
    lower: true
    digits: true
  register: payara_passwords
  no_log: true
  run_once: true
  delegate_to: localhost

- name: Generate API keys for external services
  community.general.random_string:
    length: 64
    special: true
    upper: true
    lower: true
    digits: true
  register: payara_api_keys
  no_log: true
  run_once: true
  delegate_to: localhost

- name: Save generated secrets to Vault file
  ansible.builtin.template:
    src: templates/payara_secrets_template.yml.j2
    dest: /tmp/generated_payara_secrets.yml
    mode: '0600'
  no_log: true
  run_once: true
  delegate_to: localhost
```

#### **Commande CLI**

```bash
# Générer un mot de passe de 32 caractères
openssl rand -base64 24 | head -c32

# Générer une API key de 64 caractères
openssl rand -base64 48 | head -c64

# Avec ansible
ansible localhost -e "msg={{ lookup('community.general.random_string', length=32, special=true) }}" -m debug
```

---

### 7. Audit de Sécurité

#### **Checklist Payara (complète)**

**Admin & Configuration**
- [ ] `payara_admin_password` dans Vault
- [ ] `payara_master_password` dans Vault
- [ ] `payara_cert_alias` dans Vault

**Databases**
- [ ] `mongo_pho_password` dans Vault
- [ ] `mongo_adg_password` dans Vault
- [ ] `mongo_hmi_password` dans Vault
- [ ] `mongo_cms_password` dans Vault
- [ ] `postgresql_password` dans Vault

**Services Externes**
- [ ] `apcm_service_twc_api_key` dans Vault
- [ ] `apcm_service_cloudloop_api_key` dans Vault
- [ ] `apcm_service_hawkbit_password` dans Vault

**Mail**
- [ ] `payara_mail_password` dans Vault

**Sécurité des fichiers**
- [ ] Tous les fichiers de mots de passe ont mode: '0600'
- [ ] Les fichiers de configuration ont mode: '0640' ou moins permissif
- [ ] Les répertoires sensibles ont mode: '0750' ou moins
- [ ] Les tâches avec secrets ont `no_log: true`
- [ ] Les fichiers Vault sont chiffrés
- [ ] Les fichiers Vault sont dans `.gitignore`

#### **Vérification des secrets non chiffrés**

```bash
# Rechercher tous les mots de passe potentiels
grep -rE "password|passwd|secret|api_key|apikey|token" \
  --include="*.yml" --include="*.yaml" --include="*.j2" --include="*.xml" \
  --exclude-dir=group_vars --exclude-dir=host_vars \
  ansible/ roles/ playbook/ | grep -v "vault_"

# Rechercher des IP ou URLs hardcodées
grep -rE "http://|https://|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" \
  --include="*.yml" --include="*.j2" \
  ansible/ roles/
```

#### **Vérification des permissions**

```bash
# Vérifier les permissions des fichiers déployés
ansible all -m command -a "find /opt/adr/payara -type f -name '*.xml' -o -name '*.txt' -o -name '*.properties' | xargs ls -la"

# Vérifier que les mots de passe ne sont pas lisibles
ansible all -m command -a "grep -r 'password=' /opt/adr/payara/glassfish/domains/ 2>/dev/null || echo 'No plaintext passwords found'"
```

---

## 📚 Références

- [Payara Server Documentation](https://docs.payara.fish/)
- [GlassFish asadmin Command Reference](https://eclipse-ee4j.github.io/glassfish/docs/6.2.5/reference-manual.pdf)
- [Community General Collection](https://docs.ansible.com/ansible/latest/collections/community/general/index.html)
- [asadmin Module Documentation](https://docs.ansible.com/ansible/latest/collections/community/general/asadmin_module.html)
- [MIGRATE.md (NGINX)](MIGRATE.md) - Pour la structure générale
- [MIGRATE-KEYCLOAK.md](MIGRATE-KEYCLOAK.md) - Pour l'intégration Keycloak
