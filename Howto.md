# Ampacimon #

## Ansible deployment ##


Directory content

    root@ip-172-20-100-11:/opt# tree -L 3
    .
    ├── ansible
    │   ├── ansible.cfg
    │   ├── Ansible_guide_pratique.md
    │   ├── ansible.log
    │   ├── cleanup_versions.yml
    │   ├── cleanup.yml
    │   ├── deinstall.yml
    │   ├── deploy.yml
    │   ├── group_vars
    │   │   ├── all_secrets.yml
    │   │   └── all.yml
    │   ├── inventory
    │   │   ├── backend.yml
    │   │   ├── dev.aws_ec2.yml
    │   │   ├── frontend.yml
    │   │   ├── hosts.multi.example.yml
    │   │   └── hosts.yml
    │   ├── playbook
    │   │   ├── cleanup.yml
    │   │   ├── deinstall.yml
    │   │   ├── deploy.yml
    │   │   ├── update_all.yml
    │   │   ├── update_keycloak.yml
    │   │   ├── update_mongodb.yml
    │   │   ├── update_nginx.yml
    │   │   ├── update_payara.yml
    │   │   └── update_postgresql.yml
    │   ├── README.md
    │   ├── roles
    │   │   ├── cleanup
    │   │   ├── common
    │   │   ├── deinstall
    │   │   ├── integrity
    │   │   ├── keycloak
    │   │   ├── mongodb
    │   │   ├── nginx
    │   │   ├── payara
    │   │   ├── postfix
    │   │   ├── postgresql
    │   │   ├── update_certs
    │   │   └── zabbix
    │   ├── scripts
    │   │   ├── create_ampacimon_structure.ps1
    │   │   ├── generate_release_vars.py
    │   │   ├── notify.sh
    │   │   ├── remove_java_config.sh
    │   │   ├── setup.sh
    │   │   ├── setup_windows.bat
    │   │   ├── validate.sh
    │   │   └── verify_deployment.sh
    │   ├── update.yml
    │   └── vars
    │       └── releases
    ├── ansible.tar.gz
    └── SOURCES
        ├── ADR-4.0.13
        │   ├── backend
        │   ├── checksums
        │   ├── frontend
        │   ├── jdk
        │   ├── keycloak
        │   ├── nginx
        │   └── payara
        └── ADR-4.0.16
            ├── backend
            ├── checksums
            ├── frontend
            ├── jdk
            ├── keycloak
            ├── nginx
            └── payara



### Ansible Setup ###

    root@ip-172-20-100-11:/opt# ./ansible/scripts/setup.sh
    Checking environment...
    Detected OS: linux
    Ansible is ready. Proceeding with collections and prerequisites...
    Starting galaxy collection install process
    Nothing to do. All requested collections are already installed. If you want to reinstall them, consider using `--force`.
    Installing python AWS dependencies (boto3, botocore)...
    Requirement already satisfied: boto3 in /usr/lib/python3/dist-packages (1.34.46)
    Requirement already satisfied: botocore in /usr/lib/python3/dist-packages (1.34.46)
    Prerequisites installed successfully.



### Ansible config ###

#### Frontend ####


    root@ip-172-20-100-11:/opt/ansible# vi inventory/frontend.yml
    all:
    vars:
        # Set this to your internal network range for security
        allowed_network_range: "172.20.0.0/16"
        # MongoDB should bind to localhost and the internal IP
        mongodb_bind_ips: "127.0.0.1,172.20.0.2"

    children:
        frontend_servers:
        hosts:
            localhost:
            ansible_host: 127.0.0.1
            # payara_type controls which WARs are deployed (frontend/backend/all)
            payara_type: frontend
        database_servers:
        hosts:
            backendhost:
            ansible_host: 10.10.10.10
        backend_servers:
        hosts:
            anotherhost:
            ansible_host: 10.10.10.10
        local:
        hosts:
            localhost:
            ansible_connection: local



#### deployment setup #### 

    root@ip-172-20-100-11:/opt# cd ansible
    root@ip-172-20-100-11:/opt/ansible# python3 scripts/generate_release_vars.py /opt/SOURCES/ADR-4.0.13/checksums  > vars/releases/ADR-4.0.13.yml

##### release/source file #####


    root@ip-172-20-100-11:/opt/ansible# cat vars/releases/ADR-4.0.13.yml
    apcm_version: ADR-4.0.13
    payara_bundle_version: 5.82.0-ADR-4.0.13
    keycloak_bundle_version: 26.4-ADR-4.0.13
    nginx_bundle_version: REPLACE_ME
    keycloak_flavor: rh
    mongodb_version: 8.0.16
    artifacts:
    adg_server:
        name: apcm-adg-server-war-ADR-4.0.13.war
        url: /opt/SOURCES/ADR-4.0.13/backend/apcm-adg-server-war-ADR-4.0.13.war
        checksum: sha256:58aaf0569b42c87fcf5079c9c8fc470bd69906c617e04566ef68c383d18a51d2
    apcm_server:
        name: apcm-server-war-ADR-4.0.13.war
        url: /opt/SOURCES/ADR-4.0.13/backend/apcm-server-war-ADR-4.0.13.war
        checksum: sha256:cd4e59b25aefd9f4e7732888325425b6c801396b3ef68df5fae59548f1a32173
    explorer_ear:
        name: ampacimon-explorer-ear-ADR-4.0.13.ear
        url: /opt/SOURCES/ADR-4.0.13/frontend/ampacimon-explorer-ear-ADR-4.0.13.ear
        checksum: sha256:d6a5df239a23388e4edbcf42fe822a220d642fbce70307c381e4d7c529b4533b
    rest_api:
        name: ampacimon-rest-api-ms-ADR-4.0.13.war
        url: /opt/SOURCES/ADR-4.0.13/frontend/ampacimon-rest-api-ms-ADR-4.0.13.war
        checksum: sha256:8c35e930ff66b8140aa76ed528d131cdc3b1ea09a88d4851097cb1f8eb57ab02
    jdk_back_linux:
        name: zulu17.62.17-ca-jdk17.0.17-linux_x64.tar.gz
        url: /opt/SOURCES/ADR-4.0.13/jdk/back/zulu17.62.17-ca-jdk17.0.17-linux_x64.tar.gz
        checksum: sha256:1dcbbed73e95dc35f5c60402a84936f6830ff43c2a0dc0037a5657dbc25472c1
    jdk_back_windows:
        name: zulu17.62.17-ca-jdk17.0.17-win_x64.zip
        url: /opt/SOURCES/ADR-4.0.13/jdk/back/zulu17.62.17-ca-jdk17.0.17-win_x64.zip
        checksum: sha256:bd8a942bb543f109a28d3eadf3ec2f29a3ee28ab53506e31d2858292f63c6949
    jdk_front_linux:
        name: zulu17.66.19-ca-jdk17.0.19-linux_x64.tar.gz
        url: /opt/SOURCES/ADR-4.0.13/jdk/front/zulu17.66.19-ca-jdk17.0.19-linux_x64.tar.gz
        checksum: sha256:ad319aabe659c18fa63fadb446026a7c7f5260f02a6159f51195735d20e7aa1c
    jdk_front_windows:
        name: zulu17.66.19-ca-jdk17.0.19-win_x64.zip
        url: /opt/SOURCES/ADR-4.0.13/jdk/front/zulu17.66.19-ca-jdk17.0.19-win_x64.zip
        checksum: sha256:463c85454c45fd3827df7ccfaa2b14f136eb972387da697a349a42867334328a
    keycloak_rh:
        name: apcm-keycloak-bundle-26.4-ADR-4.0.13-Keycloak-RedHat.zip
        url: /opt/SOURCES/ADR-4.0.13/keycloak/apcm-keycloak-bundle-26.4-ADR-4.0.13-Keycloak-RedHat.zip
        checksum: sha256:c6ad22582ceaf102c0e7aeef7033d86921c266796c0c8022e6a324f704771ced
    keycloak_standard:
        name: apcm-keycloak-bundle-26.4-ADR-4.0.13-Keycloak.zip
        url: /opt/SOURCES/ADR-4.0.13/keycloak/apcm-keycloak-bundle-26.4-ADR-4.0.13-Keycloak.zip
        checksum: sha256:724bcc987aeca755f7a77cda9bff669ef86f32fdc285ed95eebdddf6bba5ed67
    payara:
        name: apcm-payara-bundle-5.82.0-ADR-4.0.13-payara-bundle.zip
        url: /opt/SOURCES/ADR-4.0.13/payara/apcm-payara-bundle-5.82.0-ADR-4.0.13-payara-bundle.zip
        checksum: sha256:41d86fe48aa20aa4c6b9e65fa4e209d4998c5f8ca092af93651fbc20da701e21


##### release/source file #####


    root@ip-172-20-100-11:/opt/ansible# python3 scripts/generate_release_vars.py /opt/SOURCES/ADR-4.0.16/checksums  > vars/releases/ADR-4.0.16.yml
    root@ip-172-20-100-11:/opt/ansible# cat vars/releases/ADR-4.0.16.yml
    apcm_version: ADR-4.0.16
    payara_bundle_version: 5.82.0-ADR-4.0.16
    keycloak_bundle_version: 26.4-ADR-4.0.17
    nginx_bundle_version: ADR-4.0.16
    keycloak_flavor: rh
    mongodb_version: 8.0.16
    artifacts:
    adg_server:
        name: apcm-adg-server-war-ADR-4.0.16.war
        url: /opt/SOURCES/ADR-4.0.16/backend/apcm-adg-server-war-ADR-4.0.16.war
        checksum: sha256:b45e379c3ee78a77190570c7f7d101df80564a5c353d8989eaf019fb550b8977
    apcm_server:
        name: apcm-server-war-ADR-4.0.16.war
        url: /opt/SOURCES/ADR-4.0.16/backend/apcm-server-war-ADR-4.0.16.war
        checksum: sha256:85f00d465cf0e14583682a01eb0712efeb150d40d0292fbdec49366ebf0279a5
    explorer_ear:
        name: ampacimon-explorer-ear-ADR-4.0.16.ear
        url: /opt/SOURCES/ADR-4.0.16/frontend/ampacimon-explorer-ear-ADR-4.0.16.ear
        checksum: sha256:bb6ad2878126017cb71f6a2bc0ac43421958799ccaa77b1dc0493e89cf980878
    rest_api:
        name: ampacimon-rest-api-ms-ADR-4.0.16.war
        url: /opt/SOURCES/ADR-4.0.16/frontend/ampacimon-rest-api-ms-ADR-4.0.16.war
        checksum: sha256:b4729bee117390696e1966500200421923c4fb33b77a2092d349a8550c1fdd3a
    jdk_back_linux:
        name: zulu17.62.17-ca-jdk17.0.17-linux_x64.tar.gz
        url: /opt/SOURCES/ADR-4.0.16/jdk/back/zulu17.62.17-ca-jdk17.0.17-linux_x64.tar.gz
        checksum: sha256:1dcbbed73e95dc35f5c60402a84936f6830ff43c2a0dc0037a5657dbc25472c1
    jdk_back_windows:
        name: zulu17.62.17-ca-jdk17.0.17-win_x64.zip
        url: /opt/SOURCES/ADR-4.0.16/jdk/back/zulu17.62.17-ca-jdk17.0.17-win_x64.zip
        checksum: sha256:bd8a942bb543f109a28d3eadf3ec2f29a3ee28ab53506e31d2858292f63c6949
    jdk_front_linux:
        name: zulu17.68.203-ca-jdk17.0.20.1-linux_x64.zip
        url: /opt/SOURCES/ADR-4.0.16/jdk/front/zulu17.68.203-ca-jdk17.0.20.1-linux_x64.zip
        checksum: sha256:1038994f151a3ff84af9fdd70d4d008b424900129f2bbcb98aa1eae943e32451
    jdk_front_windows:
        name: zulu17.68.203-ca-jdk17.0.20.1-win_x64.zip
        url: /opt/SOURCES/ADR-4.0.16/jdk/front/zulu17.68.203-ca-jdk17.0.20.1-win_x64.zip
        checksum: sha256:552a335d5342c800fd03b45a23bb1136f5aa5562193542ece506d8c44b0c60d9
    keycloak_standard:
        name: apcm-keycloak-bundle-26.4-ADR-4.0.16-Keycloak.zip
        url: /opt/SOURCES/ADR-4.0.16/keycloak/apcm-keycloak-bundle-26.4-ADR-4.0.16-Keycloak.zip
        checksum: sha256:c3e6b61b49bec7072be9b856b6be68272c493de428a7d4b2a883684c378fd911
    keycloak_rh:
        name: apcm-keycloak-bundle-26.4-ADR-4.0.17-Keycloak-RedHat.zip
        url: /opt/SOURCES/ADR-4.0.16/keycloak/apcm-keycloak-bundle-26.4-ADR-4.0.17-Keycloak-RedHat.zip
        checksum: sha256:7af1acbd5c2fa66a8abddfc90e6111e9bef402b3782f47573e9d23e3a89bf607
    nginx:
        name: apcm-nginx-bundle-ADR-4.0.16-nginx-bundle.zip
        url: /opt/SOURCES/ADR-4.0.16/nginx/apcm-nginx-bundle-ADR-4.0.16-nginx-bundle.zip
        checksum: sha256:3c903439e19600470e2ef383b823c35682fa574134e9020833ed8b88f1245007
    payara:
        name: apcm-payara-bundle-5.82.0-ADR-4.0.16-payara-bundle.zip
        url: /opt/SOURCES/ADR-4.0.16/payara/apcm-payara-bundle-5.82.0-ADR-4.0.16-payara-bundle.zip
        checksum: sha256:aac7af1711408c24ef86b882bee2e04ffeae38a40e85eefabd3cfbf5796efc57






### general vars ###

    root@ip-172-20-100-11:/opt/ansible# cat group_vars/all.yml
    # Installation paths
    ansible_validate_certs: true
    adr_base_path_linux: "/opt/adr"
    adr_base_path_windows: 'C:\adr'

    # Component Paths and Service Names
    keycloak_symlink_path_linux: "/opt/keycloak"
    keycloak_symlink_path_windows: 'C:\adr\keycloak'
    keycloak_service_name_linux: "keycloak"

    payara_symlink_path_linux: "/opt/payara"
    payara_symlink_path_windows: 'C:\adr\payara'

    nginx_service_name_linux: "nginx"
    nginx_symlink_path_linux: "/opt/nginx"
    mongodb_service_name_linux: "mongod"
    mongodb_symlink_path_linux: "/opt/mongodb"
    postgresql_service_name_linux: "postgresql"
    postgresql_symlink_path_linux: "/opt/postgresql"

    # Postfix Configuration
    postfix_relay_host: "REPLACE_ME_RELAY_IP"
    postfix_relay_port: "587"
    postfix_relay_user: "REPLACE_ME_USER"
    postfix_relay_password: "bigstrongpassword"
    postfix_from_address: "REPLACE_ME_FROM@example.com"
    postfix_enabled: false

    # Default Release (can be overridden with -e @vars/releases/X.Y.Z.yml)
    # Currently points to ADR-4.0.9 as the latest default.
    # NOTE: Version-specific variables and checksums are now moved to vars/releases/
    include_release_vars: "vars/releases/ADR-4.0.16.yml"

    # Multi-server Service Discovery
    # Logic: use specific groups if defined, otherwise fallback to backend or all hosts.
    postgresql_host: "{{ (groups['database_servers'] | default([]) | length > 0) | ternary(groups['database_servers'] | first, (groups['backend_servers'] | default([]) | length > 0) | ternary(groups['backend_servers'] | first, 'localhost')) }}"
    mongodb_host: "{{ (groups['database_servers'] | default([]) | length > 0) | ternary(groups['database_servers'] | first, (groups['backend_servers'] | default([]) | length > 0) | ternary(groups['backend_servers'] | first, 'localhost')) }}"
    #keycloak_host: "{{ (groups['frontend_servers'] | default([]) | length > 0) | ternary(groups['frontend_servers'] | first, 'localhost') }}"

    # Keycloak host: frontend server if defined, otherwise localhost.
    # Backend servers render 'disabled' in the Payara configuration (see roles/payara/templates/config.properties.j2).
    keycloak_host: "{{ (groups['frontend_servers'] | default([]) | length > 0) | ternary(groups['frontend_servers'] | first, 'localhost') }}"


    backend_payara_host: "{{ (groups['backend_servers'] | default([]) | length > 0) | ternary(groups['backend_servers'] | first, 'localhost') }}"

    # Network Security
    # Default range allowed to connect to databases (PostgreSQL/MongoDB)
    # In multi-server setup, this should be set to your internal subnet (e.g., 10.0.0.0/24)
    allowed_network_range: "172.20.0.0.1/16"

    # MongoDB bind interfaces (e.g., "127.0.0.1,10.0.0.2")
    # Default to listening on all interfaces in multi-server, but restricted via firewall or allowed_network_range logic if possible.
    # Here we use a variable for manual control.
    mongodb_bind_ips: "127.0.0.1"

    # PostgreSQL Configuration
    customer_name: "customer"
    postgresql_version: "14"
    postgresql_admin_user: "adr_superadmin"
    postgresql_enabled: false




### secrets ###

    cat group_vars/all_secrets.yml
    # Secrets (to be encrypted with Ansible Vault)
    keycloak_admin_password: "admin"
    payara_admin_password: "admin"
    postgresql_admin_password: "StrongAdminPassword123!"
    postgresql_adr_keycloak_password: "StrongKeycloakPassword123!"
    postgresql_adr_customer_password: "StrongAdrCustomerPassword123!"


## RUN ADR-4.0.13 ##

    ansible-playbook -i inventory/frontend.yml --limit localhost -e @vars/releases/ADR-4.0.13.yml deploy.yml