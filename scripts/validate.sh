#!/bin/bash
# =============================================================================
# SCRIPT: validate.sh
# PROJET: APCM Deployment Ansible Repository (anziple)
# DESCRIPTION: Validation pre-deploiement pour les pipelines Jenkins
# UTILISATION: ./scripts/validate.sh [release]
#              Release par defaut: 4.0.9
# =============================================================================
set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables par defaut
RELEASE=${1:-4.0.9}
VAULT_PASSWORD_FILE=${VAULT_PASSWORD_FILE:-$PROJECT_ROOT/.vault_pass}

# Chemins
INVENTORY_FILE="$PROJECT_ROOT/inventory/hosts.yml"
PLAYBOOK_FILE="$PROJECT_ROOT/playbook/deploy.yml"
RELEASE_FILE="$PROJECT_ROOT/vars/releases/${RELEASE}.yml"
GROUP_VARS_FILE="$PROJECT_ROOT/group_vars/all.yml"
GROUP_VARS_SECRETS="$PROJECT_ROOT/group_vars/all_secrets.yml"

# =============================================================================
# FONCTIONS
# =============================================================================
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    case $level in
        "ERROR")   echo -e "${RED}[${timestamp}] [ERROR] ${message}${NC}" >&2 ;;
        "WARNING") echo -e "${YELLOW}[${timestamp}] [WARNING] ${message}${NC}" ;;
        "INFO")    echo -e "${BLUE}[${timestamp}] [INFO] ${message}${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[${timestamp}] [SUCCESS] ${message}${NC}" ;;
        *)         echo -e "[${timestamp}] [${level}] ${message}" ;;
    esac
}

validate_file() {
    local file=$1
    local description=$2

    if [ ! -f "$file" ]; then
        log "ERROR" "Fichier manquant: $file ($description)"
        return 1
    fi

    if [ ! -r "$file" ]; then
        log "ERROR" "Fichier non lisible: $file"
        return 1
    fi

    log "INFO" "Fichier validé: $file"
    return 0
}

validate_command() {
    local command=$1
    local description=$2

    if ! command -v "$command" &>/dev/null; then
        log "ERROR" "Commande manquante: $command ($description)"
        return 1
    fi

    log "INFO" "Commande validée: $command"
    return 0
}

validate_yaml_syntax() {
    local file=$1
    log "INFO" "Vérification de la syntaxe YAML: $file"

    if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1; then
        log "ERROR" "Erreur de syntaxe YAML dans: $file"
        return 1
    fi

    log "SUCCESS" "Syntax YAML valide: $file"
    return 0
}

validate_ansible_syntax() {
    local playbook=$1
    log "INFO" "Vérification de la syntaxe Ansible: $playbook"

    if ! ansible-playbook "$playbook" --syntax-check -i "$INVENTORY_FILE" 2>&1; then
        log "ERROR" "Erreur de syntaxe dans le playbook Ansible"
        return 1
    fi

    log "SUCCESS" "Syntax Ansible valide"
    return 0
}

validate_inventory() {
    local inventory=$1
    log "INFO" "Vérification de l'inventory: $inventory"

    if ! ansible-inventory --list -i "$inventory" &>/dev/null; then
        log "ERROR" "Erreur dans l'inventory file"
        return 1
    fi

    log "SUCCESS" "Inventory valide"
    return 0
}

validate_ansible_vault() {
    log "INFO" "Vérification de la configuration Ansible Vault..."

    # Vérifier que le fichier de mot de passe vault existe
    if [ -f "$VAULT_PASSWORD_FILE" ]; then
        log "INFO" "Fichier vault password trouvé: $VAULT_PASSWORD_FILE"
    else
        log "WARNING" "Aucun fichier vault password trouvé. Assurez-vous d'avoir --ask-vault-pass dans votre pipeline."
    fi

    # Vérifier que le fichier de secrets existe (chiffré ou non)
    if [ -f "$GROUP_VARS_SECRETS" ]; then
        if grep -q '\$ANSIBLE_VAULT;' "$GROUP_VARS_SECRETS" 2>/dev/null || \
           grep -q '!vault' "$GROUP_VARS_SECRETS" 2>/dev/null; then
            log "INFO" "Variables chiffrées détectées dans group_vars/all_secrets.yml"
        else
            log "WARNING" "group_vars/all_secrets.yml n'est pas chiffré avec Ansible Vault."
        fi
    else
        log "ERROR" "Fichier manquant: $GROUP_VARS_SECRETS (voir group_vars/all_secrets.yml.example)"
        return 1
    fi

    return 0
}

validate_release_vars() {
    log "INFO" "Vérification des variables de release: $RELEASE_FILE"

    if ! validate_file "$RELEASE_FILE" "fichier de release"; then
        return 1
    fi

    if ! validate_yaml_syntax "$RELEASE_FILE"; then
        return 1
    fi

    if ! python3 - "$RELEASE_FILE" <<'PYEOF'
import sys
import yaml

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

artifacts = data.get("artifacts") or {}
missing = [name for name, art in artifacts.items() if not art or not art.get("name") or not art.get("url")]
if missing:
    print(f"Artefacts incomplets (name/url manquants): {', '.join(sorted(missing))}")
    sys.exit(1)
PYEOF
    then
        log "ERROR" "Artefacts invalides dans: $RELEASE_FILE"
        return 1
    fi

    log "SUCCESS" "Variables de release valides: $RELEASE_FILE"
    return 0
}

validate_aws_connection() {
    log "INFO" "Vérification de la connexion AWS..."

    local identity
    if ! identity=$(aws sts get-caller-identity 2>&1); then
        log "WARNING" "Échec de la connexion AWS: $identity (ignoré si déploiement sans aws_ec2 inventory)"
        return 0
    fi

    local account_id=$(echo "$identity" | jq -r '.Account')
    local user_id=$(echo "$identity" | jq -r '.UserId')
    local arn=$(echo "$identity" | jq -r '.Arn')

    log "INFO" "Connecté à AWS: Account=$account_id, User=$user_id"
    log "INFO" "ARN: $arn"
    return 0
}

# =============================================================================
# VALIDATION PRINCIPALE
# =============================================================================
main() {
    log "INFO" "=========================================="
    log "INFO" "DEBUT: Validation pre-deploiement APCM (anziple)"
    log "INFO" "Release: $RELEASE"
    log "INFO" "=========================================="

    local errors=0

    # 1. Vérification des commandes requises
    log "INFO" ""
    log "INFO" "--- 1. Vérification des commandes requises ---"

    for cmd in ansible ansible-playbook python3; do
        if ! validate_command "$cmd" "requis pour le déploiement APCM"; then
            errors=$((errors + 1))
        fi
    done

    # 2. Vérification des fichiers projet
    log "INFO" ""
    log "INFO" "--- 2. Vérification des fichiers projet ---"

    for file in "$INVENTORY_FILE" "$PLAYBOOK_FILE" "$RELEASE_FILE" "$GROUP_VARS_FILE" "$GROUP_VARS_SECRETS"; do
        if ! validate_file "$file" "fichier projet"; then
            errors=$((errors + 1))
        fi
    done

    # 3. Vérification de la syntaxe YAML
    log "INFO" ""
    log "INFO" "--- 3. Vérification de la syntaxe YAML ---"

    for yaml_file in "$INVENTORY_FILE" "$RELEASE_FILE" "$GROUP_VARS_FILE"; do
        if [ -f "$yaml_file" ]; then
            if ! validate_yaml_syntax "$yaml_file"; then
                errors=$((errors + 1))
            fi
        fi
    done

    # 4. Vérification des variables de release
    log "INFO" ""
    log "INFO" "--- 4. Vérification des variables de release ---"

    if ! validate_release_vars; then
        errors=$((errors + 1))
    fi

    # 5. Vérification de l'inventory
    log "INFO" ""
    log "INFO" "--- 5. Vérification de l'inventory ---"

    if ! validate_inventory "$INVENTORY_FILE"; then
        errors=$((errors + 1))
    fi

    # 6. Vérification de la syntaxe Ansible
    log "INFO" ""
    log "INFO" "--- 6. Vérification de la syntaxe Ansible ---"

    if ! validate_ansible_syntax "$PLAYBOOK_FILE"; then
        errors=$((errors + 1))
    fi

    # 7. Vérification de la configuration Vault
    log "INFO" ""
    log "INFO" "--- 7. Vérification de la configuration Vault ---"

    if ! validate_ansible_vault; then
        errors=$((errors + 1))
    fi

    # 8. Vérification de la connexion AWS (optionnelle)
    log "INFO" ""
    log "INFO" "--- 8. Vérification de la connexion AWS (optionnelle) ---"

    if ! validate_aws_connection; then
        errors=$((errors + 1))
    fi

    # =============================================================================
    # RESULTAT
    # =============================================================================

    log "INFO" ""
    log "INFO" "=========================================="
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "Toutes les validations ont passé!"
        log "SUCCESS" "Prêt pour le déploiement."
        log "INFO" "=========================================="
        exit 0
    else
        log "ERROR" "$errors validation(s) ont échoué!"
        log "ERROR" "Corrigez les erreurs avant de continuer."
        log "INFO" "=========================================="
        exit 1
    fi
}

# Execution
main "$@"
