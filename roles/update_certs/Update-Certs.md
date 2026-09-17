Structure finale
ansible/roles/update_certs/
├── defaults/
│   └── main.yml              # Variables par défaut (inclut S3)
├── handlers/
│   └── main.yml              # Handlers pour redémarrer les services
└── tasks/
    ├── main.yml              # Point d'entrée principal
    ├── setup.yml             # Configuration des facts
    ├── download.yml          # Téléchargement depuis S3
    ├── linux.yml             # Tâches Linux
    └── windows.yml           # Tâches Windows
Nouveautés pour S3
defaults/main.yml
---
# Update certificates specific configuration
update_certs_enabled: false

# Certificate paths (local)
update_certs_cert_dest: "/etc/ssl/certs"
update_certs_cert_src: ""

update_certs_key_dest: "/etc/ssl/private"
update_certs_key_src: ""

# S3 configuration (alternative)
update_certs_cert_s3_bucket: ""
update_certs_cert_s3_object: ""
update_certs_key_s3_bucket: ""
update_certs_key_s3_object: ""

# Temporary download directory
update_certs_temp_dir: "/tmp/certs"

# File permissions
update_certs_owner: "root"
update_certs_group: "root"
update_certs_mode: "0644"
tasks/download.yml
Gère le téléchargement des fichiers depuis S3 pour Linux et Windows (les modules AWS acceptent les forward slashes)
tasks/setup.yml
Calcule automatiquement les chemins effectifs :
•  use_s3_cert / use_s3_key : booléens indiquant si S3 est utilisé
•  cert_filename / key_filename : noms de fichiers extraits
Utilisation
Depuis S3 :
- role: update_certs
  vars:
    update_certs_enabled: true
    update_certs_cert_s3_bucket: "mon-bucket"
    update_certs_cert_s3_object: "certs/prod/certificate.crt"
    update_certs_key_s3_bucket: "mon-bucket"
    update_certs_key_s3_object: "certs/prod/private.key"
Depuis local :
- role: update_certs
  vars:
    update_certs_enabled: true
    update_certs_cert_src: "files/certs/certificate.crt"
    update_certs_key_src: "files/certs/private.key"
Note : La collection amazon.aws doit être installée (déjà présente dans le projet via scripts/setup.sh).