#!/bin/bash
# =============================================================================
# SCRIPT: verify_deployment.sh
# PROJET: deploymatic (Ansible Deployment)
# DESCRIPTION: Vérification post-déploiement pour confirmer le succès
# UTILISATION: ./scripts/verify_deployment.sh [environment] [release_version]
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
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables par défaut
ENVIRONMENT=${1:-dev}
RELEASE_VERSION=${2:-unknown}
INVENTORY_FILE="$PROJECT_ROOT/inventory/hosts.yml"
GROUP_VARS_FILE="$PROJECT_ROOT/group_vars/all.yml"

# Timeouts (en secondes)
SSH_TIMEOUT=30
HTTP_TIMEOUT=10

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
        "TITLE")   echo -e "${CYAN}[${timestamp}] [${message}]${NC}" ;;
        "CHECK")   echo -e "${MAGENTA}[${timestamp}] [CHECK] ${message}${NC}" ;;
        *)         echo -e "[${timestamp}] [${level}] ${message}" ;;
    esac
}

get_ansible_hosts() {
    local group=$1
    ansible-inventory --list -i "$INVENTORY_FILE" | jq -r ".${group}[] | .ansible_host // .ansible_ssh_host // empty" 2>/dev/null || echo ""
}

get_ansible_hostnames() {
    local group=$1
    ansible-inventory --list -i "$INVENTORY_FILE" | jq -r ".${group}[] | .name // empty" 2>/dev/null || echo ""
}

test_ssh_connectivity() {
    local host=$1
    local timeout=$2
    local port=${3:-22}
    
    log "CHECK" "Test de connectivité SSH vers: $host:$port (timeout: ${timeout}s)"
    
    if timeout "$timeout" bash -c "nc -z -w 5 $host $port" 2>/dev/null; then
        log "SUCCESS" "SSH: $host:$port est accessible"
        return 0
    else
        log "ERROR" "SSH: Impossible de se connecter à $host:$port"
        return 1
    fi
}

test_http_endpoint() {
    local url=$1
    local expected_status=${2:-200}
    local timeout=${3:-10}
    
    log "CHECK" "Test de endpoint HTTP: $url (attendu: $expected_status)"
    
    local status_code
    if status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null); then
        if [ "$status_code" = "$expected_status" ]; then
            log "SUCCESS" "HTTP: $url → $status_code OK"
            return 0
        else
            log "ERROR" "HTTP: $url → $status_code (attendu: $expected_status)"
            return 1
        fi
    else
        log "ERROR" "HTTP: Impossible d'atteindre $url"
        return 1
    fi
}

test_tcp_port() {
    local host=$1
    local port=$2
    local timeout=${3:-5}
    
    log "CHECK" "Test de port TCP: $host:$port"
    
    if timeout "$timeout" bash -c "nc -z -w 5 $host $port" 2>/dev/null; then
        log "SUCCESS" "TCP: $host:$port est ouvert"
        return 0
    else
        log "ERROR" "TCP: $host:$port est fermé ou inaccessible"
        return 1
    fi
}

check_payara() {
    local host=$1
    local port=${2:-4848}
    
    log "TITLE" "Vérification Payara sur $host"
    
    # Vérifier le port admin
    if ! test_tcp_port "$host" "$port"; then
        return 1
    fi
    
    # Vérifier l'application (port 8080)
    if ! test_tcp_port "$host" 8080; then
        log "WARNING" "Port application 8080 non accessible sur $host"
    fi
    
    return 0
}

check_keycloak() {
    local host=$1
    local port=${2:-8080}
    local protocol="http"
    
    log "TITLE" "Vérification Keycloak sur $host"
    
    # Vérifier le port
    if ! test_tcp_port "$host" "$port"; then
        return 1
    fi
    
    # Vérifier l'endpoint health
    local url="${protocol}://${host}:${port}/auth/realms/master"
    if ! test_http_endpoint "$url" 200; then
        log "WARNING" "Keycloak realm master non accessible"
    fi
    
    return 0
}

check_nginx() {
    local host=$1
    local port=${2:-80}
    
    log "TITLE" "Vérification NGINX sur $host"
    
    # Vérifier le port HTTP
    if ! test_tcp_port "$host" "$port"; then
        return 1
    fi
    
    # Vérifier la page par défaut ou health check
    local url="http://${host}:${port}"
    if ! test_http_endpoint "$url" 200; then
        # Essayer le health check
        url="http://${host}:${port}/health"
        test_http_endpoint "$url" 200 || return 1
    fi
    
    return 0
}

check_postgresql() {
    local host=$1
    local port=${2:-5432}
    
    log "TITLE" "Vérification PostgreSQL sur $host"
    
    if ! test_tcp_port "$host" "$port"; then
        return 1
    fi
    
    # Optionnel: tester la connexion avec psql si disponible
    if command -v psql &>/dev/null; then
        log "INFO" "Test de connexion PostgreSQL..."
        # On ne teste pas la connexion car on n'a pas les credentials
        # Mais on pourrait utiliser ansible pour vérifier le service
    fi
    
    return 0
}

check_mongodb() {
    local host=$1
    local port=${2:-27017}
    
    log "TITLE" "Vérification MongoDB sur $host"
    
    if ! test_tcp_port "$host" "$port"; then
        return 1
    fi
    
    return 0
}

check_service_via_ansible() {
    local host=$1
    local service_name=$2
    
    log "CHECK" "Vérification du service $service_name sur $host"
    
    # Utiliser ansible pour vérifier que le service est démarré
    # Note: Cela nécessite que l'hôte soit dans l'inventory
    local result
    if result=$(ansible "$host" -i "$INVENTORY_FILE" -m "service_facts" -a "" 2>&1); then
        if echo "$result" | grep -q "\"${service_name}\":.*\"state\": \"running\""; then
            log "SUCCESS" "Service $service_name est en cours d'exécution sur $host"
            return 0
        else
            log "WARNING" "Service $service_name n'est pas en cours d'exécution sur $host"
            return 1
        fi
    else
        log "ERROR" "Impossible de vérifier le service $service_name via Ansible"
        return 1
    fi
}

verify_all_services() {
    local errors=0
    
    # Récupérer tous les hôtes
    log "INFO" "Récupération des hôtes depuis l'inventory..."
    
    local all_hosts=()
    local host
    
    # Lire les hosts depuis l'inventory
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        all_hosts+=("$host")
    done < <(ansible-inventory --list -i "$INVENTORY_FILE" | jq -r '.all.hosts[] | .ansible_host // .ansible_ssh_host // .name' 2>/dev/null || echo "")
    
    if [ ${#all_hosts[@]} -eq 0 ]; then
        log "WARNING" "Aucun hôte trouvé dans l'inventory"
        return 0
    fi
    
    log "INFO" "Hôtes trouvés: ${all_hosts[*]}"
    log "INFO" ""
    
    # Vérifier chaque hôte
    for host in "${all_hosts[@]}"; do
        log "INFO" "=========================================="
        log "INFO" "Vérification de: $host"
        log "INFO" "=========================================="
        
        # 1. Vérifier la connectivité SSH
        if ! test_ssh_connectivity "$host" "$SSH_TIMEOUT"; then
            errors=$((errors + 1))
            continue
        fi
        
        # 2. Vérifier les services par type d'hôte
        # Déterminer le rôle de l'hôte
        local host_type=$(ansible-inventory --list -i "$INVENTORY_FILE" | \
            jq -r --arg h "$host" '.all.hosts[] | select(.ansible_host == $h or .ansible_ssh_host == $h or .name == $h) | .payara_type // "all"' 2>/dev/null || echo "all")
        
        log "INFO" "Type d'hôte détecté: $host_type"
        
        # Vérifier les ports par défaut
        local ports_to_check=(80 443 8080 8443 22 4848 27017 5432)
        for port in "${ports_to_check[@]}"; do
            test_tcp_port "$host" "$port" 5 || true
        done
        
        # Vérifier les services spécifiques
        case $host_type in
            "frontend")
                check_payara "$host" || errors=$((errors + 1))
                check_keycloak "$host" || errors=$((errors + 1))
                check_nginx "$host" || errors=$((errors + 1))
                ;;
            "backend")
                check_payara "$host" || errors=$((errors + 1))
                check_postgresql "$host" || errors=$((errors + 1))
                check_mongodb "$host" || errors=$((errors + 1))
                ;;
            "all"|*)
                check_payara "$host" || errors=$((errors + 1))
                check_keycloak "$host" || errors=$((errors + 1))
                check_nginx "$host" || errors=$((errors + 1))
                check_postgresql "$host" || errors=$((errors + 1))
                check_mongodb "$host" || errors=$((errors + 1))
                ;;
        esac
        
        log "INFO" ""
    done
    
    return $errors
}

verify_application_health() {
    log "TITLE" "Vérification de la santé des applications"
    
    local errors=0
    local frontend_hosts=()
    local host
    
    # Récupérer les hôtes frontend
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        frontend_hosts+=("$host")
    done < <(get_ansible_hosts "frontend_servers")
    
    # Si pas de frontend_servers, essayer all
    if [ ${#frontend_hosts[@]} -eq 0 ]; then
        while IFS= read -r host; do
            [ -z "$host" ] && continue
            frontend_hosts+=("$host")
        done < <(get_ansible_hosts "all")
    fi
    
    if [ ${#frontend_hosts[@]} -eq 0 ]; then
        log "WARNING" "Aucun hôte frontend trouvé"
        return 0
    fi
    
    for host in "${frontend_hosts[@]}"; do
        # Vérifier l'application principale
        local app_url="http://${host}"
        log "CHECK" "Vérification de l'application: $app_url"
        
        if test_http_endpoint "$app_url" 200; then
            log "SUCCESS" "Application accessible sur $app_url"
        else
            errors=$((errors + 1))
        fi
    done
    
    return $errors
}

verify_database_health() {
    log "TITLE" "Vérification de la santé des bases de données"
    
    local errors=0
    local db_hosts=()
    local host
    
    # Récupérer les hôtes de base de données
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        db_hosts+=("$host")
    done < <(get_ansible_hosts "database_servers")
    
    # Si pas de database_servers, essayer backend_servers
    if [ ${#db_hosts[@]} -eq 0 ]; then
        while IFS= read -r host; do
            [ -z "$host" ] && continue
            db_hosts+=("$host")
        done < <(get_ansible_hosts "backend_servers")
    fi
    
    if [ ${#db_hosts[@]} -eq 0 ]; then
        log "INFO" "Aucun hôte de base de données dédié trouvé. Vérification des ports sur tous les hôtes."
        return 0
    fi
    
    for host in "${db_hosts[@]}"; do
        # PostgreSQL
        check_postgresql "$host" && log "SUCCESS" "PostgreSQL OK sur $host" || errors=$((errors + 1))
        
        # MongoDB
        check_mongodb "$host" && log "SUCCESS" "MongoDB OK sur $host" || errors=$((errors + 1))
    done
    
    return $errors
}

generate_deployment_report() {
    local env=$1
    local version=$2
    local status=$3
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local report_file="$PROJECT_ROOT/deployment_reports/deploymatic_${env}_${version}_${timestamp}.report"
    
    log "INFO" "Génération du rapport de déploiement: $report_file"
    
    mkdir -p "$PROJECT_ROOT/deployment_reports"
    
    cat > "$report_file" <<EOF
# Rapport de Déploiement - deploymatic

**Date:** $(date +"%Y-%m-%d %H:%M:%S")
**Environnement:** $env
**Version:** $version
**Statut:** $status
**Exécuté par:** $(whoami)
**Hostname:** $(hostname)

## Résumé des Vérifications

$(cat "$PROJECT_ROOT/.verify_log" 2>/dev/null || echo "Aucun log de vérification trouvé")

## Configuration Déployée

### Variables d'Environnement
- PROJET: SDT-BE-ADR-DEV
- Région AWS: eu-central-1
- VPC CIDR: 172.20.0.0/16

### Composants
- [ ] Payara Application Server
- [ ] Keycloak Identity Provider
- [ ] NGINX Reverse Proxy
- [ ] MongoDB Database
- [ ] PostgreSQL Database

## Commandes Utilisées
```bash
# Validation
./scripts/validate.sh $env

# Déploiement
ansible-playbook -i inventory/hosts.yml playbook/deploy.yml \\
    -e @vars/$env.yml \\
    -e "release_version=$version" \\
    --ask-vault-pass

# Vérification
./scripts/verify_deployment.sh $env $version
```

---
*Rapport généré automatiquement par verify_deployment.sh*
EOF
    
    log "SUCCESS" "Rapport généré: $report_file"
    
    # Afficher le rapport
    cat "$report_file"
}

# =============================================================================
# VÉRIFICATION PRINCIPALE
# =============================================================================

main() {
    log "INFO" "============================================================"
    log "INFO" "DEBUT: Vérification post-déploiement deploymatic"
    log "INFO" "Environnement: $ENVIRONMENT"
    log "INFO" "Version: $RELEASE_VERSION"
    log "INFO" "============================================================"
    
    local errors=0
    local verify_log="$PROJECT_ROOT/.verify_log"
    
    # Rediriger la sortie vers un log file
    exec 3> "$verify_log"
    exec 2>&3
    
    # 1. Vérification des services
    log "INFO" ""
    log "TITLE" "ETAPE 1: Vérification de tous les services"
    log "INFO" "--------------------------------------------"
    
    if ! verify_all_services; then
        errors=$((errors + 1))
    fi
    
    # 2. Vérification de la santé des applications
    log "INFO" ""
    log "TITLE" "ETAPE 2: Vérification de la santé des applications"
    log "INFO" "----------------------------------------------------"
    
    if ! verify_application_health; then
        errors=$((errors + 1))
    fi
    
    # 3. Vérification de la santé des bases de données
    log "INFO" ""
    log "TITLE" "ETAPE 3: Vérification de la santé des bases de données"
    log "INFO" "--------------------------------------------------------"
    
    if ! verify_database_health; then
        errors=$((errors + 1))
    fi
    
    # 4. Vérification des logs Ansible
    log "INFO" ""
    log "TITLE" "ETAPE 4: Vérification des logs Ansible"
    log "INFO" "---------------------------------------"
    
    local ansible_log="$PROJECT_ROOT/ansible.log"
    if [ -f "$ansible_log" ]; then
        log "INFO" "Dernières lignes du log Ansible:"
        tail -20 "$ansible_log" | while read line; do
            log "INFO" "  $line"
        done
        
        # Vérifier s'il y a eu des erreurs
        if grep -q "failed=[1-9]" "$ansible_log" 2>/dev/null; then
            log "ERROR" "Des tâches Ansible ont échoué!"
            errors=$((errors + 1))
        fi
    else
        log "WARNING" "Aucun log Ansible trouvé"
    fi
    
    # Fermer le log file
    exec 3>&-
    
    # =============================================================================
    # RESULTAT
    # =============================================================================
    
    log "INFO" ""
    log "INFO" "============================================================"
    
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "Toutes les vérifications ont passé!"
        log "SUCCESS" "Déploiement réussi pour deploymatic v$RELEASE_VERSION vers $ENVIRONMENT"
        generate_deployment_report "$ENVIRONMENT" "$RELEASE_VERSION" "SUCCESS"
        exit 0
    else
        log "ERROR" "$errors vérification(s) ont échoué!"
        log "ERROR" "Déploiement partiellement réussi - Vérifiez les logs"
        generate_deployment_report "$ENVIRONMENT" "$RELEASE_VERSION" "PARTIAL"
        exit 1
    fi
}

# Execution
main "$@"
