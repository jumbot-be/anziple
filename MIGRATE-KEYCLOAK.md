# Migration Keycloak : Remplacement des Scripts par Ansible

## 📋 Contexte

Le déploiement **Keycloak** actuel utilise une architecture similaire à NGINX avec :
- Des **bundles** contenant des scripts shell et Apache Ant
- Des **fichiers de configuration avec tokens** (`@variable@`)
- Un **système de filtrage** via Ant (`build.xml`)
- Des **scripts d'installation et de configuration** interactifs

**Bundle analysé** : `apcm-keycloak-bundle-26.4-4.0.11-Keycloak-RedHat` (Keycloak 26.4)

---

## 🔍 Analyse des Composants Actuels

### Structure du Bundle Keycloak

```
apcm-keycloak-bundle/
├── prepare-config.sh          # Appelle Ant pour filtrer les tokens
├── build.xml                  # Définition des tâches Ant
├── profiles/
│   └── template/
│       └── config.properties  # Variables par défaut (key=value)
├── resources/
│   ├── conf/                 # Fichiers de configuration
│   │   ├── keycloak.conf      # Configuration principale Keycloak
│   │   ├── quarkus.properties # Configuration Quarkus
│   │   ├── apcm-realm-realm.json # Realm JSON
│   │   └── maintenance.ini   # Config pour les scripts de maintenance
│   ├── certs/                # Certificats SSL
│   │   ├── default-cert.cnf  # Template pour les certificats
│   │   └── ffdhe2048.txt     # Paramètres DH
│   ├── scripts/              # Scripts d'installation et service
│   │   ├── bash-scripts/     # Scripts Linux
│   │   │   ├── _create-cronjob.sh
│   │   │   ├── keycloak-setup-service.sh
│   │   │   ├── keycloak-remove-service.sh
│   │   │   └── ...
│   │   └── posh/             # Scripts Windows (PowerShell)
│   │       ├── _create-schtask.ps1
│   │       ├── install-service.ps1
│   │       └── uninstall-service.ps1
│   └── lib/                  # Bibliothèques JDBC (MSSQL)
│       ├── mssql-jdbc_auth-12.6.1.x64.dll
│       └── mssql-jdbc-12.6.1.jre11.jar
└── keycloak/                # Distribution Keycloak
    ├── bin/                  # Scripts Keycloak
    ├── lib/                  # Bibliothèques
    └── ...
```

### Mécanisme de Filtrage (Ant)

Le script `prepare-config.sh` appelle Ant qui :
1. Copie les fichiers binaires sans filtrage
2. Charge `profiles/<profile>/config.properties` comme filtre
3. **Ajoute un filtre supplémentaire** : `kc.home.directory=${basedir}/keycloak`
4. Copie tous les autres fichiers **AVEC filtrage** (remplace `@token@`)
5. **Correction post-filtrage** : `sed -i 's@:443"@"@g' generated/conf/apcm-realm-realm.json`

### Tokens Identifiés (Keycloak)

| **Catégorie** | **Token** | **Variable Ansible** | **Description** |
|--------------|-----------|---------------------|-----------------|
| **Java** | `@keycloak.java.home@` | `keycloak_java_home` | Répertoire JDK/Keycloak |
| **Network** | `@ext.host.fqdn@` | `ext_host_fqdn` | FQDN externe |
| **Network** | `@proxy.host.fqdn@` | `proxy_host_fqdn` | FQDN du proxy |
| **Keycloak** | `@keycloak.host.fqdn@` | `keycloak_host_fqdn` | FQDN de Keycloak |
| **Keycloak** | `@keycloak.prefix@` | `keycloak_prefix` | Préfixe des clients |
| **Keycloak** | `@keycloak.proxy.prop@` | `keycloak_proxy_prop` | Propriétés proxy |
| **Keycloak** | `@keycloak.facing.redir.port@` | `keycloak_facing_redir_port` | Port de redirection |
| **Keycloak** | `@keycloak.listen.https.port@` | `keycloak_listen_https_port` | Port d'écoute HTTPS |
| **Keycloak** | `@keycloak.cpuaffinity@` | `keycloak_cpuaffinity` | Affinité CPU |
| **Database** | `@keycloak.database@` | `keycloak_database_type` | Type de DB (postgres/mssql) |
| **Database** | `@keycloak.database.url@` | `keycloak_database_url` | URL de la DB |
| **Database** | `@keycloak.database.user@` | `keycloak_db_user` | Utilisateur DB |
| **Database** | `@keycloak.database.password@` | `keycloak_db_password` | Mot de passe DB |
| **Mail** | `@keycloak.mail.*@` | `keycloak_mail_*` | Configuration mail |
| **Paths** | `@keycloak.datadir@` | `keycloak_datadir` | Répertoire des données |
| **Paths** | `@kc.home.directory@` | `kc_home_directory` | Répertoire home Keycloak (géré par Ant) |

---

## 📦 Scripts à Remplacer

### 1️⃣ `prepare-config.sh` + Ant + `build.xml`

**Fonction** : Filtre les tokens `@...@` dans les fichiers de configuration.

**Spécificités Keycloak** :
- Ajoute un filtre supplémentaire : `kc.home.directory=${basedir}/keycloak`
- Effectue une correction post-filtrage : `sed -i 's@:443"@"@g' generated/conf/apcm-realm-realm.json`

**Remplacement** :
- ✅ **Templates Jinja2** pour chaque fichier de configuration
- ✅ **Variables centralisées** dans `group_vars/all.yml`
- ✅ **Module `template`** d'Ansible pour le rendu
- ✅ **Tâche de correction** pour le problème des `:443`

**Statut** : ✅ Solution validée (approche similaire à NGINX)

---

### 2️⃣ `1-keycloak--setup.sh` (Script Principal d'Installation)

#### **Fonctionnalités par OS**

##### **🪟 Windows et 🐧 Linux**

**1. Préparation**
```bash
KEYCLOAK_HOME="keycloak"

# Vérifie que Keycloak est installé
if [ ! -d "${KEYCLOAK_HOME}" ]; then
    echo "Keycloak not installed"
    exit -1
fi

chmod -R +x $KEYCLOAK_HOME/bin
chmod -R +x ./generated
```

**2. Arrêt et suppression du service existant**
```bash
./generated/scripts/bash-scripts/keycloak-remove-service.sh
```

**3. Récupération de JAVA_HOME**
```bash
JAVA_HOME=$(grep "JAVA_HOME=" generated/scripts/systemd/keycloak.service | ...)
export JAVA_HOME=$JAVA_HOME
$JAVA_HOME/bin/java -version
```

**4. Nettoyage des anciens certificats**
```bash
rm -f apcm-cert.pem apcm-cert-key.pem keycloak.p12
```

**5. Génération des certificats SSL**
```bash
# Génération de la paire de clés
openssl req -x509 -days 365 -newkey rsa:2048 -new -nodes -sha256 \
  -keyout apcm-cert-key.pem -out apcm-cert.pem -config generated/certs/default-cert.cnf

# Conversion en PKCS12
openssl pkcs12 -export -in apcm-cert.pem -inkey apcm-cert-key.pem \
  -name keycloak -password pass:password > keycloak.p12

# Import dans le keystore Keycloak
$JAVA_HOME/bin/keytool -importkeystore -srckeystore keycloak.p12 \
  -srcstorepass password -destkeystore $KEYCLOAK_HOME/conf/server.keystore \
  -srcstoretype pkcs12 -alias keycloak -keypass password -storepass password

# Nettoyage
rm apcm-cert.pem apcm-cert-key.pem keycloak.p12
chmod -R 750 $KEYCLOAK_HOME/conf
```

**6. Configuration de Keycloak**
```bash
# Copie des fichiers de configuration
cp generated/conf/keycloak.conf $KEYCLOAK_HOME/conf
cp generated/conf/quarkus.properties $KEYCLOAK_HOME/conf
mkdir -p $KEYCLOAK_HOME/data/import
cp generated/conf/apcm-realm-realm.json $KEYCLOAK_HOME/data/import
```

**7. Build de la distribution Quarkus**
```bash
# Linux
./$KEYCLOAK_HOME/bin/kc.sh build --http-relative-path=/auth --vault=file \
  --spi-user-profile-declarative-user-profile-admin-read-only-attributes=filterMask \
  --spi-user-profile-declarative-user-profile-read-only-attributes=filterMask

# Windows
powershell.exe -executionpolicy bypass -Command "..."
```

**8. Installation du service**
```bash
./generated/scripts/bash-scripts/keycloak-setup-service.sh
```

#### **Variables Utilisées**

```bash
KEYCLOAK_HOME="keycloak"
```

#### **Fichiers Utilisés**

- `generated/certs/default-cert.cnf` (template pour openssl)
- `generated/scripts/systemd/keycloak.service` (service systemd)
- `generated/scripts/bash-scripts/keycloak-remove-service.sh`
- `generated/scripts/bash-scripts/keycloak-setup-service.sh`

#### **Problèmes Identifiés**

| Problème | Impact | Solution Ansible |
|----------|--------|------------------|
| **Hardcoded JAVA_HOME extraction** | Parsing fragile | Variable Ansible directe |
| **Génération certificats interactive** | Non automatisable | Module `community.crypto` |
| **Copie manuelle des fichiers** | Pas idempotent | Module `template`/`copy` |
| **Build Quarkus requis** | Long et complexe | Pré-build ou module dédié |
| **Paths hardcodés** | Pas flexible | Variables Ansible |

#### **Solution Ansible**

```yaml
# roles/keycloak/tasks/setup.yml

# ============================================================
# Étape 1 : Vérifier que Keycloak est installé
# ============================================================

- name: Check if Keycloak directory exists
  ansible.builtin.stat:
    path: "{{ keycloak_home }}"
  register: keycloak_dir
  tags: [keycloak, install]

- name: Fail if Keycloak not installed
  ansible.builtin.fail:
    msg: "Keycloak is not installed. Please install it first at {{ keycloak_home }}"
  when: not keycloak_dir.stat.exists
  tags: [keycloak, install]

# ============================================================
# Étape 2 : Définir JAVA_HOME
# ============================================================

- name: Set JAVA_HOME
  ansible.builtin.set_fact:
    java_home: "{{ common_java_home | default('/opt/jdk17') }}"
  tags: [keycloak, java]

- name: Verify Java is available
  ansible.builtin.command: "{{ java_home }}/bin/java -version"
  register: java_version
  changed_when: false
  tags: [keycloak, java]

# ============================================================
# Étape 3 : Arrêter et désinstaller le service existant
# ============================================================

- name: Include remove service tasks
  ansible.builtin.include_tasks: remove_service.yml
  tags: [keycloak, service]

# ============================================================
# Étape 4 : Générer les certificats SSL
# ============================================================

- name: Include certificate setup tasks
  ansible.builtin.include_tasks: setup_certificate.yml
  tags: [keycloak, cert]

# ============================================================
# Étape 5 : Déployer la configuration
# ============================================================

- name: Create Keycloak config directories
  ansible.builtin.file:
    path: "{{ keycloak_home }}/{{ item }}"
    state: directory
    mode: '0755'
    owner: root
    group: root
  loop:
    - conf
    - data/import
  tags: [keycloak, config]

- name: Deploy keycloak.conf
  ansible.builtin.template:
    src: conf/keycloak.conf.j2
    dest: "{{ keycloak_home }}/conf/keycloak.conf"
    mode: '0644'
    owner: root
    group: root
  tags: [keycloak, config]

- name: Deploy quarkus.properties
  ansible.builtin.template:
    src: conf/quarkus.properties.j2
    dest: "{{ keycloak_home }}/conf/quarkus.properties"
    mode: '0644'
    owner: root
    group: root
  tags: [keycloak, config]

- name: Deploy realm JSON (with :443 fix)
  ansible.builtin.template:
    src: conf/apcm-realm-realm.json.j2
    dest: "{{ keycloak_home }}/data/import/apcm-realm-realm.json"
    mode: '0644'
    owner: root
    group: root
  tags: [keycloak, config]

- name: Apply :443 fix in realm JSON
  ansible.builtin.replace:
    path: "{{ keycloak_home }}/data/import/apcm-realm-realm.json"
    regexp: '"https://[^"]+:443"'
    replace: '"https:\1"'
  when: keycloak_fix_443 | default(true)
  tags: [keycloak, config]

# ============================================================
# Étape 6 : Build Quarkus (si nécessaire)
# ============================================================

- name: Check if Keycloak needs build
  ansible.builtin.stat:
    path: "{{ keycloak_home }}/bin/kc.sh"
  register: kc_script
  tags: [keycloak, build]

- name: Build Keycloak Quarkus distribution
  ansible.builtin.command: >
    ./kc.sh build
    --http-relative-path=/auth
    --vault=file
    --spi-user-profile-declarative-user-profile-admin-read-only-attributes=filterMask
    --spi-user-profile-declarative-user-profile-read-only-attributes=filterMask
  args:
    chdir: "{{ keycloak_home }}"
    creates: "{{ keycloak_home }}/.build_complete"
  register: keycloak_build
  until: keycloak_build is succeeded
  retries: 3
  delay: 30
  tags: [keycloak, build]

- name: Mark build as complete
  ansible.builtin.file:
    path: "{{ keycloak_home }}/.build_complete"
    state: touch
    mode: '0644'
  when: keycloak_build is succeeded
  tags: [keycloak, build]

# ============================================================
# Étape 7 : Installer le service
# ============================================================

- name: Include service setup tasks
  ansible.builtin.include_tasks: setup_service.yml
  tags: [keycloak, service]
```

---

### 3️⃣ `2-keycloak--deploy-cron.sh` (Déploiement des Tâches Cron)

**Code Source** :
```bash
#!/bin/bash
if [ "$OSTYPE" == "linux-gnu" ]; then 
    echo "Deploying cron tab"
    ./generated/scripts/bash-scripts/_create-cronjob.sh
elif [ "$OSTYPE" == "msys" ]; then
    echo "Deploying Scheduled task"
    schtaskscript=$(cygpath -w "${currentdir}/generated/scripts/posh/_create-schtask.ps1")
    powershell.exe -executionpolicy bypass -Command "Start-Process ... -verb runas -wait"
fi
```

**Identique à NGINX** : Ce script est le même que pour NGINX, il appelle juste les scripts spécifiques Keycloak.

**Solution Ansible** : Voir la solution pour NGINX dans `MIGRATE.md` et adapter pour Keycloak.

---

### 4️⃣ `keycloak-setup-service.sh` (Installation du Service)

#### **Fonctionnalités**

**Linux** :
```bash
# Crée un lien symbolique /opt/keycloak
rm /opt/keycloak > /dev/null 2>&1
ln -s `pwd`/$KEYCLOAK_HOME /opt/keycloak

# Crée l'utilisateur et le groupe
groupadd -r $USR_GRP
useradd -r -g $USR_GRP -d /opt/keycloak -s /sbin/nologin keycloak

chown -R $USR_GRP:$USR_GRP $KEYCLOAK_HOME/
chown -R $USR_GRP:$USR_GRP /opt/keycloak
chmod o+x /opt/keycloak/bin

# Désinstalle l'ancien service
./uninstall-service.sh > /dev/null

# Installe le nouveau service via systemd
./install-service.sh

# Copie la configuration CPU affinity
mkdir -p /etc/systemd/system/payara_ampacimon-domain.service.d
cp generated/services/overrides.conf /etc/systemd/system/keycloak.service.d/override.conf

# Recharge systemd
systemctl daemon-reload
systemctl enable keycloak
systemctl start keycloak
```

**Windows** :
```bash
# Désinstalle l'ancien service
sc query keycloak >/dev/null
if [ $? == 0 ]; then
    powershell.exe -executionpolicy bypass -Command "Start-Process ... uninstall-service.ps1"
fi

# Installe le nouveau service
powershell.exe -executionpolicy bypass -Command "Start-Process ... install-service.ps1"
```

**Variables** :
```bash
KEYCLOAK_HOME="keycloak"
USR_GRP="keycloak"
```

#### **Solution Ansible**

```yaml
# roles/keycloak/tasks/setup_service_linux.yml

- name: Create symlink to /opt/keycloak
  ansible.builtin.file:
    src: "{{ playbook_dir }}/{{ keycloak_bundle_path }}/keycloak"
    dest: /opt/keycloak
    state: link
    force: yes
  tags: [keycloak, service]

- name: Create keycloak group
  ansible.builtin.group:
    name: keycloak
    state: present
    system: yes
  tags: [keycloak, service]

- name: Create keycloak user
  ansible.builtin.user:
    name: keycloak
    group: keycloak
    home: /opt/keycloak
    shell: /sbin/nologin
    system: yes
    state: present
  tags: [keycloak, service]

- name: Set permissions on Keycloak directory
  ansible.builtin.file:
    path: "{{ keycloak_home }}"
    state: directory
    recurse: yes
    owner: keycloak
    group: keycloak
    mode: '0750'
  tags: [keycloak, service]

- name: Set executable permissions on bin directory
  ansible.builtin.file:
    path: "{{ keycloak_home }}/bin"
    state: directory
    recurse: yes
    mode: '0755'
  tags: [keycloak, service]

- name: Copy systemd override configuration
  ansible.builtin.copy:
    src: services/overrides.conf
    dest: /etc/systemd/system/keycloak.service.d/override.conf
    mode: '0644'
  tags: [keycloak, service]

- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: yes
  tags: [keycloak, service]

- name: Enable and start Keycloak service
  ansible.builtin.systemd:
    name: keycloak
    state: started
    enabled: yes
  tags: [keycloak, service]
```

```yaml
# roles/keycloak/tasks/setup_service_windows.yml

- name: Uninstall existing Keycloak service (Windows)
  ansible.windows.win_command: >
    sc query keycloak >nul 2>&1 && (
      powershell.exe -executionpolicy bypass -Command "& { Start-Process ... uninstall-service.ps1 -verb runas -wait }"
    )
  ignore_errors: yes
  tags: [keycloak, service, windows]

- name: Install Keycloak service (Windows)
  ansible.windows.win_command: >
    powershell.exe -executionpolicy bypass -Command "& { Start-Process ... install-service.ps1 -verb runas -wait }"
  register: service_install
  until: service_install.rc == 0
  retries: 3
  delay: 10
  tags: [keycloak, service, windows]
```

---

### 5️⃣ `keycloak-remove-service.sh` (Suppression du Service)

**Code Source** :
```bash
if [ "$OSTYPE" == "linux-gnu" ]; then
    cd generated/scripts/systemd
    chmod +x *.sh
    ./uninstall-service.sh > /dev/null
elif [ "$OSTYPE" == "msys" ]; then
    sc query keycloak >/dev/null
    if [ $? == 0 ]; then
        currentdir=$(pwd)
        scriptpath=$(cygpath -w "${currentdir}/generated/scripts/posh/uninstall-service.ps1")
        powershell.exe -executionpolicy bypass -Command "Start-Process ... -verb runas -wait"
    fi
fi
```

**Solution Ansible** :

```yaml
# roles/keycloak/tasks/remove_service.yml

- name: Stop Keycloak service (Linux)
  ansible.builtin.systemd:
    name: keycloak
    state: stopped
  ignore_errors: yes
  when: ansible_facts['os_family'] != 'Windows'
  tags: [keycloak, remove]

- name: Disable Keycloak service (Linux)
  ansible.builtin.systemd:
    name: keycloak
    enabled: no
  ignore_errors: yes
  when: ansible_facts['os_family'] != 'Windows'
  tags: [keycloak, remove]

- name: Remove systemd override (Linux)
  ansible.builtin.file:
    path: /etc/systemd/system/keycloak.service.d
    state: absent
  when: ansible_facts['os_family'] != 'Windows'
  tags: [keycloak, remove]

- name: Remove symlink /opt/keycloak
  ansible.builtin.file:
    path: /opt/keycloak
    state: absent
  when: ansible_facts['os_family'] != 'Windows'
  tags: [keycloak, remove]

- name: Uninstall Keycloak service (Windows)
  ansible.windows.win_command: >
    sc query keycloak >nul 2>&1 && (
      powershell.exe -executionpolicy bypass -Command "& { Start-Process ... uninstall-service.ps1 -verb runas -wait }"
    )
  ignore_errors: yes
  when: ansible_facts['os_family'] == 'Windows'
  tags: [keycloak, remove]
```

---

### 6️⃣ `_create-cronjob.sh` (Création de la Tâche Cron Linux)

**Identique à NGINX** mais pour Keycloak.

**Variables spécifiques** :
- `service="Keycloak"` (au lieu de "Scriptuser")
- Fichiers différents : `exportKeycloakLogs.sh`

**Solution Ansible** : Adapter la solution NGINX pour Keycloak.

---

### 7️⃣ `_create-schtask.ps1` (Création des Tâches Planifiées Windows)

**Identique à NGINX** mais pour Keycloak.

**Solution Ansible** : Adapter la solution NGINX pour Keycloak.

---

## 🎯 Solutions Complètes par Script

### 🔹 Remplacement de `prepare-config.sh` + Ant

**Identique à NGINX** mais avec :
- Filtrage supplémentaire `kc.home.directory`
- Correction post-filtrage pour `:443`

**Solution** : Utiliser les templates Jinja2 + une tâche de correction.

---

### 🔹 Remplacement de `1-keycloak--setup.sh`

```yaml
# roles/keycloak/tasks/setup.yml

- name: Verify Keycloak installation
  ansible.builtin.stat:
    path: "{{ keycloak_home }}"
  register: keycloak_check

- name: Fail if Keycloak not installed
  ansible.builtin.fail:
    msg: "Keycloak not found at {{ keycloak_home }}"
  when: not keycloak_check.stat.exists

- name: Set JAVA_HOME
  ansible.builtin.set_fact:
    java_home: "{{ common_java_home | default('/opt/jdk17') }}"

- name: Remove existing service
  ansible.builtin.include_tasks: remove_service.yml

- name: Setup SSL certificates
  ansible.builtin.include_tasks: setup_certificate.yml

- name: Create config directories
  ansible.builtin.file:
    path: "{{ keycloak_home }}/{{ item }}"
    state: directory
    mode: '0755'
  loop:
    - conf
    - data/import

- name: Deploy configuration files
  ansible.builtin.template:
    src: "conf/{{ item }}.j2"
    dest: "{{ keycloak_home }}/conf/{{ item }}"
    mode: '0644'
  loop:
    - keycloak.conf
    - quarkus.properties

- name: Deploy realm JSON
  ansible.builtin.template:
    src: conf/apcm-realm-realm.json.j2
    dest: "{{ keycloak_home }}/data/import/apcm-realm-realm.json"
    mode: '0644'

- name: Fix :443 in realm JSON
  ansible.builtin.replace:
    path: "{{ keycloak_home }}/data/import/apcm-realm-realm.json"
    regexp: '"https://[^"]+:443"'
    replace: '"https:\1"'

- name: Build Keycloak Quarkus
  ansible.builtin.command: ./kc.sh build --http-relative-path=/auth --vault=file
  args:
    chdir: "{{ keycloak_home }}"
    creates: "{{ keycloak_home }}/.build_complete"

- name: Setup Keycloak service
  ansible.builtin.include_tasks: setup_service.yml
```

---

### 🔹 Remplacement de `setup_certificate.yml` (Certificats SSL)

```yaml
# roles/keycloak/tasks/setup_certificate.yml

- name: Create certs directory
  ansible.builtin.file:
    path: "{{ keycloak_home }}/certs"
    state: directory
    mode: '0755'

- name: Generate self-signed certificate
  community.crypto.openssl_certificate:
    path: "{{ keycloak_home }}/certs/keycloak-cert.crt"
    privatekey_path: "{{ keycloak_home }}/certs/keycloak-cert.key"
    csr_path: "{{ keycloak_home }}/certs/keycloak-cert.csr"
    provider: selfsigned
    selfsigned_not_after: +{{ keycloak_cert_validity_days | default(365) }}d
    selfsigned_digest: sha256
    selfsigned_subject:
      CN: "{{ keycloak_host_fqdn }}"
      O: "{{ keycloak_cert_organization | default('Ampacimon') }}"
      OU: "{{ keycloak_cert_ou | default('IT') }}"
      C: "{{ keycloak_cert_country | default('BE') }}"
    selfsigned_dns:
      - "{{ keycloak_host_fqdn }}"
  when: keycloak_cert_type == 'selfsigned'

- name: Convert to PKCS12
  community.crypto.openssl_pkcs12:
    path: "{{ keycloak_home }}/certs/keycloak.p12"
    privatekey_path: "{{ keycloak_home }}/certs/keycloak-cert.key"
    certificate_path: "{{ keycloak_home }}/certs/keycloak-cert.crt"
    state: present
    friendly_name: keycloak
    password: "{{ keycloak_keystore_password | default('password') }}"

- name: Import to Java keystore
  community.general.java_keystore:
    name: keycloak
    certificate: "{{ keycloak_home }}/certs/keycloak-cert.crt"
    private_key: "{{ keycloak_home }}/certs/keycloak-cert.key"
    dest: "{{ keycloak_home }}/conf/server.keystore"
    password: "{{ keycloak_keystore_password | default('password') }}"
    alias: keycloak
    state: present

- name: Clean up temporary files
  ansible.builtin.file:
    path: "{{ keycloak_home }}/certs/{{ item }}"
    state: absent
  loop:
    - keycloak-cert.crt
    - keycloak-cert.key
    - keycloak-cert.csr
    - keycloak.p12

- name: Set permissions on certs
  ansible.builtin.file:
    path: "{{ keycloak_home }}/certs"
    state: directory
    recurse: yes
    mode: '0640'
    owner: root
    group: root
```

---

## 📊 Mapping des Variables Keycloak

```yaml
# group_vars/all.yml

# ============================================================
# Keycloak - Base Configuration
# ============================================================
keycloak_home: "/opt/adr/keycloak"  # Répertoire d'installation
keycloak_java_home: "{{ common_java_home | default('/opt/jdk17') }}"
keycloak_host_fqdn: "auth.{{ domain }}"
keycloak_prefix: "local"
keycloak_proxy_prop: "proxy-headers=xforwarded"
keycloak_facing_redir_port: 443
keycloak_listen_https_port: 8543
keycloak_cpuaffinity: "0,1"

# ============================================================
# Keycloak - Database Configuration
# ============================================================
keycloak_database_type: "postgres"  # postgres, mssql
keycloak_database_url: "jdbc:postgresql://{{ postgresql_host }}:5432/{{ keycloak_db_name }}?ssl=true&sslmode=prefer"
keycloak_db_user: "keycloak_usr"
keycloak_db_password: "{{ vault_keycloak_db_password }}"
keycloak_db_name: "keycloak_db"

# ============================================================
# Keycloak - SSL Configuration
# ============================================================
keycloak_cert_type: "selfsigned"  # selfsigned, custom, existing
keycloak_cert_validity_days: 365
keycloak_keystore_password: "{{ vault_keycloak_keystore_password }}"
keycloak_cert_country: "BE"
keycloak_cert_state: "Liegge"
keycloak_cert_locality: "Loncin"
keycloak_cert_organization: "Ampacimon"
keycloak_cert_ou: "IT"

# ============================================================
# Keycloak - Mail Configuration
# ============================================================
keycloak_mail_auth: true
keycloak_mail_host: "smtp.{{ domain }}"
keycloak_mail_port: 587
keycloak_mail_user: "keycloak@{{ domain }}"
keycloak_mail_password: "{{ vault_keycloak_mail_password }}"
keycloak_mail_sender: "keycloak@{{ domain }}"
keycloak_mail_ssl: true
keycloak_mail_replyto: "noreply@{{ domain }}"

# ============================================================
# Keycloak - Data Directories
# ============================================================
keycloak_datadir: "/opt/adr/data/keycloak"
keycloak_datadir_user: ""
keycloak_datadir_password: ""

# ============================================================
# Keycloak - Service Configuration
# ============================================================
keycloak_service_user: "keycloak"
keycloak_service_group: "keycloak"

# ============================================================
# Keycloak - Network
# ============================================================
ext_host_fqdn: "{{ domain }}"
proxy_host_fqdn: "localhost"
```

---

## 📝 Checklist de Migration Keycloak

### ✅ À Faire

- [ ] **Préparation**
  - [ ] Créer la structure `roles/keycloak/templates/`
  - [ ] Copier les fichiers de `resources/` vers `templates/`
  - [ ] Convertir chaque fichier en template Jinja2

- [ ] **Templates**
  - [ ] `conf/keycloak.conf.j2`
  - [ ] `conf/quarkus.properties.j2`
  - [ ] `conf/apcm-realm-realm.json.j2`
  - [ ] `conf/maintenance.ini.j2`
  - [ ] `certs/default-cert.cnf.j2`

- [ ] **Tâches Ansible**
  - [ ] `tasks/main.yml`
  - [ ] `tasks/setup.yml` (remplace `1-keycloak--setup.sh`)
  - [ ] `tasks/setup_certificate.yml`
  - [ ] `tasks/setup_service.yml`
  - [ ] `tasks/setup_service_linux.yml`
  - [ ] `tasks/setup_service_windows.yml`
  - [ ] `tasks/remove_service.yml`
  - [ ] `tasks/deploy_cron.yml`
  - [ ] `tasks/deploy_cron_linux.yml`
  - [ ] `tasks/deploy_cron_windows.yml`

- [ ] **Variables**
  - [ ] Définir toutes les variables dans `group_vars/all.yml`
  - [ ] Créer `group_vars/all_secrets.yml` (encrypted)
  - [ ] Définir les defaults dans `roles/keycloak/defaults/main.yml`

- [ ] **Tests**
  - [ ] Tester l'installation
  - [ ] Tester le déploiement des configurations
  - [ ] Tester les certificats SSL
  - [ ] Tester le service Keycloak
  - [ ] Vérifier que Keycloak démarre correctement

- [ ] **Nettoyage**
  - [ ] Supprimer les références aux scripts dans la documentation
  - [ ] Mettre à jour le README

---

## 💡 Conseils Spécifiques Keycloak

### 1. **Gestion de Quarkus Build**

Le build Quarkus peut être long. Options :

**Option A : Pré-build dans le bundle**
- Fournir une version pré-build de Keycloak
- Éviter le build pendant le déploiement

**Option B : Build conditionnel**
```yaml
- name: Check if build is needed
  ansible.builtin.stat:
    path: "{{ keycloak_home }}/.build_complete"
  register: build_check

- name: Build Keycloak
  ansible.builtin.command: ./kc.sh build
  args:
    chdir: "{{ keycloak_home }}"
  when: not build_check.stat.exists
```

**Option C : Utiliser un role dédié**
- Créer un role `keycloak-build` séparé
- Appeler ce role uniquement quand nécessaire

### 2. **Gestion des Versions de Keycloak**

Keycloak 26.4 utilise Quarkus. Les anciennes versions utilisaient WildFly.

**Variables pour gérer les différences** :
```yaml
keycloak_version: "26.4"
keycloak_distribution_type: "quarkus"  # quarkus, wildfly
keycloak_build_command: >
  {% if keycloak_distribution_type == 'quarkus' %}
    ./kc.sh build --http-relative-path=/auth --vault=file
  {% else %}
    # Commandes pour WildFly
  {% endif %}
```

### 3. **Gestion des Realms**

**Option A : Importer le realm via l'API**
```yaml
- name: Import realm via API
  uri:
    url: "https://{{ keycloak_host_fqdn }}:{{ keycloak_listen_https_port }}/auth/admin/realms"
    method: POST
    user: "{{ keycloak_admin_user }}"
    password: "{{ keycloak_admin_password }}"
    body: "{{ lookup('file', 'conf/apcm-realm-realm.json') }}"
    body_format: json
    headers:
      Content-Type: application/json
```

**Option B : Copier le fichier JSON** (actuelle)
- Copier dans `keycloak/data/import/`
- Keycloak l'importe automatiquement au démarrage

### 4. **Gestion des Mots de Passe**

Les mots de passe sont stockés dans des fichiers `secrets/` dans le bundle.

**Solution Ansible** :
```yaml
# Créer les fichiers de secrets via template
- name: Create password aliases
  ansible.builtin.template:
    src: "secrets/{{ item }}.j2"
    dest: "{{ keycloak_home }}/secrets/{{ item }}"
    mode: '0600'
  loop:
    - apcm-service-phoenix-file
    - apcm-mail-file
    # ... autres fichiers de secrets
```

---

## 🚀 Commandes Utiles

### Pour extraire les tokens des fichiers Keycloak

```bash
# Trouver tous les tokens dans les fichiers Keycloak
find TMP-CONFIG/sources/keycloak -type f -name "*.conf" -o -name "*.properties" -o -name "*.json" | \
  xargs grep -oh '@[a-zA-Z0-9._-]*@' | sort -u
```

### Pour tester la configuration Keycloak

```bash
# Tester que Keycloak démarre
/opt/adr/keycloak/bin/kc.sh start

# Tester l'API
curl -v https://localhost:8543/auth/realms/master
```

---

## 🔐 Intégration Ansible Vault - Gestion des Secrets

**IMPÉRATIF** : Tous les mots de passe, clés, certificats et secrets Keycloak doivent être stockés dans **Ansible Vault** et jamais en clair.

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

---

### 2. Structure des Secrets pour Keycloak

#### **Fichier `group_vars/all_secrets.yml` (à chiffrer)**

```yaml
# ============================================================
# Keycloak - Database Credentials
# ============================================================
keycloak_database: "{{ vault_keycloak_database }}"           # postgres ou mssql
keycloak_database_url: "{{ vault_keycloak_database_url }}"
keycloak_db_user: "{{ vault_keycloak_db_user }}"
keycloak_db_password: "{{ vault_keycloak_db_password }}"

# ============================================================
# Keycloak - Admin Credentials
# ============================================================
keycloak_admin_user: "{{ vault_keycloak_admin_user }}"
keycloak_admin_password: "{{ vault_keycloak_admin_password }}"

# ============================================================
# Keycloak - SSL/TLS Configuration
# ============================================================
keycloak_keystore_password: "{{ vault_keycloak_keystore_password }}"
keycloak_keystore_file: "/opt/adr/keycloak/conf/keystore.p12"
keycloak_truststore_password: "{{ vault_keycloak_truststore_password }}"
keycloak_truststore_file: "/opt/adr/keycloak/conf/truststore.p12"

# ============================================================
# Keycloak - Mail Configuration
# ============================================================
keycloak_mail_host: "{{ vault_keycloak_mail_host }}"
keycloak_mail_port: "{{ vault_keycloak_mail_port }}"
keycloak_mail_user: "{{ vault_keycloak_mail_user }}"
keycloak_mail_password: "{{ vault_keycloak_mail_password }}"
keycloak_mail_from: "{{ vault_keycloak_mail_from }}"

# ============================================================
# Keycloak - Proxy Configuration
# ============================================================
keycloak_proxy_prop: "{{ vault_keycloak_proxy_prop }}"
```

#### **Fichier `group_vars/prod_secrets.yml` (exemple production)**

```yaml
# ============================================================
# Keycloak - Production Database (PostgreSQL)
# ============================================================
vault_keycloak_database: "postgres"
vault_keycloak_database_url: "jdbc:postgresql://prod-db.example.com:5432/keycloak"
vault_keycloak_db_user: "keycloak_prod"
vault_keycloak_db_password: "{{ random_password_32_chars }}"

# ============================================================
# Keycloak - Production Admin
# ============================================================
vault_keycloak_admin_user: "admin"
vault_keycloak_admin_password: "{{ random_password_32_chars }}"

# ============================================================
# Keycloak - Production SSL
# ============================================================
vault_keycloak_keystore_password: "{{ random_password_16_chars }}"
vault_keycloak_truststore_password: "{{ random_password_16_chars }}"

# ============================================================
# Keycloak - Production Mail (SMTP)
# ============================================================
vault_keycloak_mail_host: "smtp.prod.example.com"
vault_keycloak_mail_port: "587"
vault_keycloak_mail_user: "keycloak@prod.example.com"
vault_keycloak_mail_password: "{{ random_password_32_chars }}"
vault_keycloak_mail_from: "keycloak@prod.example.com"

# ============================================================
# Keycloak - Production Proxy
# ============================================================
vault_keycloak_proxy_prop: "reenc"
```

---

### 3. Commandes de Chiffrement/Déchiffrement

#### **Créer et éditer des fichiers Vault**

```bash
# Créer un nouveau fichier Vault interactif
ansible-vault create group_vars/prod_secrets.yml

# Éditer un fichier Vault existant
ansible-vault edit group_vars/prod_secrets.yml

# Chiffrer un fichier existant
ansible-vault encrypt group_vars/all_secrets.yml

# Déchiffrer pour visualisation (ne pas commiter déchiffré!)
ansible-vault view group_vars/prod_secrets.yml

# Déchiffrer temporairement
ansible-vault decrypt group_vars/prod_secrets.yml --output /tmp/temp_secrets.yml
```

#### **Changer le mot de passe du Vault**

```bash
ansible-vault rekey group_vars/prod_secrets.yml
```

---

### 4. Intégration avec les Playbooks

#### **Exécution avec Vault**

```bash
# Avec demande interactive du mot de passe
ansible-playbook keycloak-deploy.yml --ask-vault-pass

# Avec fichier de mot de passe
ansible-playbook keycloak-deploy.yml --vault-password-file ~/.vault_pass.txt

# Avec variable d'environnement
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass.txt
ansible-playbook keycloak-deploy.yml
```

#### **Exemple de playbook Keycloak avec Vault**

```yaml
---
- name: Deploy Keycloak Configuration
  hosts: keycloak_servers
  vars_files:
    - group_vars/all.yml
    - group_vars/all_secrets.yml
  
  tasks:
    - name: Include environment-specific secrets
      ansible.builtin.include_vars:
        file: "group_vars/{{ environment }}_secrets.yml"
      no_log: true
      when: environment is defined
      
    - name: Create Keycloak data directory
      ansible.builtin.file:
        path: "{{ keycloak_datadir }}"
        state: directory
        owner: keycloak
        group: keycloak
        mode: '0750'
      
    - name: Deploy keycloak.conf
      ansible.builtin.template:
        src: conf/keycloak.conf.j2
        dest: "{{ keycloak_home }}/conf/keycloak.conf"
        owner: keycloak
        group: keycloak
        mode: '0640'
      no_log: true
      
    - name: Deploy database configuration
      ansible.builtin.template:
        src: conf/quarkus.properties.j2
        dest: "{{ keycloak_home }}/conf/quarkus.properties"
        owner: keycloak
        group: keycloak
        mode: '0640'
      no_log: true
```

---

### 5. Bonnes Pratiques de Sécurité

#### **Dans les playbooks et templates**

```yaml
# TOUJOURS utiliser no_log: true pour les secrets
- name: Deploy realm configuration
  ansible.builtin.template:
    src: conf/apcm-realm-realm.json.j2
    dest: "{{ keycloak_home }}/data/import/apcm-realm-realm.json"
    owner: keycloak
    group: keycloak
    mode: '0640'
  no_log: true

# Permissions strictes sur les fichiers de secrets
- name: Create password aliases directory
  ansible.builtin.file:
    path: "{{ keycloak_home }}/secrets"
    state: directory
    owner: keycloak
    group: keycloak
    mode: '0750'

- name: Deploy password alias files
  ansible.builtin.template:
    src: "secrets/{{ item }}.j2"
    dest: "{{ keycloak_home }}/secrets/{{ item }}"
    owner: keycloak
    group: keycloak
    mode: '0600'  # Uniquement le propriétaire peut lire
  loop:
    - apcm-service-phoenix-file
    - apcm-mail-file
  no_log: true
```

#### **Variables sensibles**

```yaml
# MAUVAIS - hardcoded dans le playbook
# keycloak_db_password: "mysecretpassword"

# BON - référence à Vault
keycloak_db_password: "{{ vault_keycloak_db_password }}"

# Dans les templates, utiliser les variables
# Exemple dans quarkus.properties.j2:
# db.password = {{ keycloak_db_password }}
```

---

### 6. Génération de Mots de Passe Aléatoires

#### **Utiliser le module Ansible**

```yaml
- name: Generate random passwords for Keycloak
  community.general.random_string:
    length: 32
    special: true
    upper: true
    lower: true
    digits: true
  register: keycloak_passwords
  no_log: true

- name: Create secrets file with generated passwords
  ansible.builtin.template:
    src: templates/secrets_template.yml.j2
    dest: /tmp/new_secrets.yml
    mode: '0600'
  no_log: true
  delegate_to: localhost
  run_once: true
```

#### **Commande CLI**

```bash
# Générer un mot de passe aléatoire
openssl rand -base64 24 | head -c32

# Avec ansible
ansible localhost -e "msg={{ lookup('community.general.random_string', length=32, special=true) }}" -m debug
```

---

### 7. Audit de Sécurité

#### **Checklist Keycloak**

- [ ] `keycloak_db_password` dans Vault et non dans `group_vars/all.yml`
- [ ] `keycloak_admin_password` dans Vault
- [ ] `keycloak_keystore_password` dans Vault
- [ ] `keycloak_mail_password` dans Vault
- [ ] Tous les fichiers de secrets ont mode: '0600' ou '0640'
- [ ] Les tâches de déploiement de secrets ont `no_log: true`
- [ ] Les fichiers Vault sont chiffrés et dans `.gitignore`
- [ ] Les secrets sont spécifiques à chaque environnement

#### **Vérification des secrets non chiffrés**

```bash
# Rechercher des mots de passe en clair
grep -rE "password|passwd|secret" \
  --include="*.yml" --include="*.yaml" --include="*.j2" \
  --exclude-dir=group_vars --exclude-dir=host_vars \
  ansible/ roles/ playbook/ | grep -v "vault_"
```

---

## 📚 Références

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak Quarkus Distribution](https://www.keycloak.org/2024/03/keycloak-2600-released.html)
- [Ansible Community Crypto Collection](https://docs.ansible.com/ansible/latest/collections/community/crypto/index.html)
- [MIGRATE.md (NGINX)](MIGRATE.md) - Pour la structure générale
