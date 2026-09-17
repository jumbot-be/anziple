#!/bin/bash
# =============================================================================
# SCRIPT: notify.sh
# PROJET: deploymatic & tfsimon
# DESCRIPTION: Script de notification pour les pipelines Jenkins
# UTILISATION: ./scripts/notify.sh [status] [environment] [project] [version]
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

# =============================================================================
# VARIABLES PAR DÉFAUT
# =============================================================================

# Récupérer depuis les paramètres ou l'environnement
BUILD_STATUS=${1:-${BUILD_STATUS:-SUCCESS}}
ENVIRONMENT=${2:-${ENVIRONMENT:-dev}}
PROJECT=${3:-${JOB_NAME:-${PROJECT:-unknown}}}
VERSION=${4:-${RELEASE_VERSION:-${BUILD_NUMBER:-unknown}}}

# Récupérer depuis Jenkins (si disponible)
BUILD_NUMBER=${BUILD_NUMBER:-0}
BUILD_URL=${BUILD_URL:-}
JOB_NAME=${JOB_NAME:-}
GIT_COMMIT=${GIT_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")}
GIT_BRANCH=${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")}

# Variables de configuration
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
SLACK_CHANNEL=${SLACK_CHANNEL:-#sdt-deployments}

EMAIL_RECIPIENTS=${EMAIL_RECIPIENTS:-}
EMAIL_FROM=${EMAIL_FROM:-jenkins@company.com}
EMAIL_SERVER=${EMAIL_SERVER:-smtp.company.com}
EMAIL_PORT=${EMAIL_PORT:-587}

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

get_status_info() {
    case $BUILD_STATUS in
        "SUCCESS"|"success")
            STATUS_ICON="✅"
            STATUS_COLOR="good"
            STATUS_TEXT="réussi"
            EMOTION=":tada:"
            ;;
        "FAILURE"|"failure")
            STATUS_ICON="❌"
            STATUS_COLOR="danger"
            STATUS_TEXT="échoué"
            EMOTION=":fire:"
            ;;
        "UNSTABLE"|"unstable")
            STATUS_ICON="⚠️"
            STATUS_COLOR="warning"
            STATUS_TEXT="instable"
            EMOTION=":warning:"
            ;;
        "ABORTED"|"aborted")
            STATUS_ICON="⏹️"
            STATUS_COLOR="danger"
            STATUS_TEXT="annulé"
            EMOTION=":x:"
            ;;
        *)
            STATUS_ICON="❓"
            STATUS_COLOR="warning"
            STATUS_TEXT="inconnu"
            EMOTION=":question:"
            ;;
    esac
}

# =============================================================================
# NOTIFICATION SLACK
# =============================================================================

send_slack_notification() {
    local webhook_url=$1
    local channel=$2
    
    if [ -z "$webhook_url" ]; then
        log "WARNING" "SLACK_WEBHOOK_URL non configuré - Notification Slack ignorée"
        return 0
    fi
    
    get_status_info
    
    # Déterminer la couleur et le message
    local color=$STATUS_COLOR
    
    # Construire le message Slack
    local message="{
        \"channel\": \"$channel\",
        \"username\": \"Jenkins-CI\",
        \"icon_emoji\": \":rocket:\",
        \"attachments\": [
            {
                \"color\": \"$color\",
                \"title\": \"${STATUS_ICON} Déploiement ${PROJECT} v${VERSION} vers ${ENVIRONMENT}\",
                \"text\": \"Statut: *${STATUS_TEXT}* ${EMOTION}\",
                \"fields\": [
                    {
                        \"title\": \"Projet\",
                        \"value\": \"${PROJECT}\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Environnement\",
                        \"value\": \"${ENVIRONMENT}\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Version\",
                        \"value\": \"${VERSION}\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Build\",
                        \"value\": \"<${BUILD_URL}|#${BUILD_NUMBER}>\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Branch\",
                        \"value\": \"${GIT_BRANCH}\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Commit\",
                        \"value\": \"${GIT_COMMIT}\",
                        \"short\": true
                    }
                ],
                \"footer\": \"Jenkins CI/CD\",
                \"ts\": $(date +%s)
            }
        ]
    }"
    
    log "INFO" "Envoi de la notification Slack à $channel..."
    
    # Envoyer la notification
    if curl -s -X POST -H 'Content-type: application/json' \
        --data "$message" \
        "$webhook_url" > /dev/null 2>&1; then
        log "SUCCESS" "Notification Slack envoyée"
        return 0
    else
        log "ERROR" "Échec de l'envoi de la notification Slack"
        return 1
    fi
}

# =============================================================================
# NOTIFICATION EMAIL
# =============================================================================

send_email_notification() {
    local recipients=$1
    
    if [ -z "$recipients" ]; then
        log "WARNING" "EMAIL_RECIPIENTS non configuré - Notification email ignorée"
        return 0
    fi
    
    get_status_info
    
    local subject="[${BUILD_STATUS}] Déploiement ${PROJECT} v${VERSION} vers ${ENVIRONMENT}"
    local body="
Déploiement: ${PROJECT}
Environnement: ${ENVIRONMENT}
Version: ${VERSION}
Statut: ${STATUS_TEXT} ${STATUS_ICON}

--- Détails ---
Build: #${BUILD_NUMBER}
URL: ${BUILD_URL}
Branch: ${GIT_BRANCH}
Commit: ${GIT_COMMIT}
Timestamp: $(date +"%Y-%m-%d %H:%M:%S")

--- Serveur ---
Hostname: $(hostname)
Exécuté par: $(whoami)
"
    
    log "INFO" "Envoi de la notification email à $recipients..."
    
    # Utiliser mail ou sendmail
    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" -r "$EMAIL_FROM" $recipients
    elif command -v sendmail &>/dev/null; then
        echo -e "Subject: $subject\nFrom: $EMAIL_FROM\nTo: $recipients\n\n$body" | sendmail -t
    else
        log "ERROR" "Aucun client mail trouvé (mail/sendmail)"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Notification email envoyée"
        return 0
    else
        log "ERROR" "Échec de l'envoi de la notification email"
        return 1
    fi
}

# =============================================================================
# NOTIFICATION MS TEAMS
# =============================================================================

send_teams_notification() {
    local webhook_url=$1
    
    if [ -z "$webhook_url" ]; then
        return 0
    fi
    
    get_status_info
    
    # MS Teams utilise des Adaptive Cards
    local message="{
        \"@type\": \"MessageCard\",
        \"@context\": \"http://schema.org/extensions\",
        \"summary\": \"${STATUS_ICON} Déploiement ${PROJECT} v${VERSION} - ${STATUS_TEXT}\",
        \"themeColor\": \"${STATUS_COLOR}\",
        \"title\": \"${STATUS_ICON} Déploiement ${PROJECT} v${VERSION} vers ${ENVIRONMENT}\",
        \"text\": \"Statut: **${STATUS_TEXT}** ${EMOTION}\",
        \"sections\": [{
            \"facts\": [
                {\"name\": \"Projet\", \"value\": \"${PROJECT}\"},
                {\"name\": \"Environnement\", \"value\": \"${ENVIRONMENT}\"},
                {\"name\": \"Version\", \"value\": \"${VERSION}\"},
                {\"name\": \"Build\", \"value\": \"[#${BUILD_NUMBER}](${BUILD_URL})\"},
                {\"name\": \"Branch\", \"value\": \"${GIT_BRANCH}\"},
                {\"name\": \"Commit\", \"value\": \"${GIT_COMMIT}\"}
            ],
            \"markdown\": true
        }],
        \"potentialAction\": [{
            \"@type\": \"OpenUri\",
            \"name\": \"Voir le build\",
            \"targets\": [{\"os\": \"default\", \"uri\": \"${BUILD_URL}\"}]
        }]
    }"
    
    log "INFO" "Envoi de la notification MS Teams..."
    
    if curl -s -X POST -H 'Content-type: application/json' \
        --data "$message" \
        "$webhook_url" > /dev/null 2>&1; then
        log "SUCCESS" "Notification MS Teams envoyée"
        return 0
    else
        log "ERROR" "Échec de l'envoi de la notification MS Teams"
        return 1
    fi
}

# =============================================================================
# NOTIFICATION DISCORD
# =============================================================================

send_discord_notification() {
    local webhook_url=$1
    
    if [ -z "$webhook_url" ]; then
        return 0
    fi
    
    get_status_info
    
    # Discord utilise des embeds
    local color_value
    case $STATUS_COLOR in
        "good") color_value=3066993 ;;
        "danger") color_value=15158332 ;;
        "warning") color_value=16776960 ;;
        *) color_value=1146986 ;;
    esac
    
    local message="{
        \"content\": \"${STATUS_ICON} **Déploiement ${PROJECT} v${VERSION} vers ${ENVIRONMENT}** - *${STATUS_TEXT}* ${EMOTION}\",
        \"embeds\": [{
            \"color\": ${color_value},
            \"title\": \"Détails du déploiement\",
            \"fields\": [
                {\"name\": \"Projet\", \"value\": \"${PROJECT}\", \"inline\": true},
                {\"name\": \"Environnement\", \"value\": \"${ENVIRONMENT}\", \"inline\": true},
                {\"name\": \"Version\", \"value\": \"${VERSION}\", \"inline\": true},
                {\"name\": \"Build\", \"value\": \"[#${BUILD_NUMBER}](${BUILD_URL})\", \"inline\": true},
                {\"name\": \"Branch\", \"value\": \"${GIT_BRANCH}\", \"inline\": true},
                {\"name\": \"Commit\", \"value\": \"${GIT_COMMIT}\", \"inline\": true}
            ],
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }]
    }"
    
    log "INFO" "Envoi de la notification Discord..."
    
    if curl -s -X POST -H 'Content-type: application/json' \
        --data "$message" \
        "$webhook_url" > /dev/null 2>&1; then
        log "SUCCESS" "Notification Discord envoyée"
        return 0
    else
        log "ERROR" "Échec de l'envoi de la notification Discord"
        return 1
    fi
}

# =============================================================================
# NOTIFICATION SYSTÈME (syslog/journalctl)
# =============================================================================

send_system_notification() {
    get_status_info
    
    local message="JENKINS DEPLOYMENT: ${STATUS_ICON} ${PROJECT} v${VERSION} -> ${ENVIRONMENT} (${STATUS_TEXT}) | Build=${BUILD_NUMBER} Branch=${GIT_BRANCH}"
    
    log "INFO" "Envoi de la notification système..."
    
    # Syslog
    if command -v logger &>/dev/null; then
        logger -t "jenkins-deploy" "$message"
    fi
    
    # Journalctl
    if command -v systemd-cat &>/dev/null; then
        echo "$message" | systemd-cat -t "jenkins-deploy" -p info
    fi
    
    log "SUCCESS" "Notification système envoyée"
    return 0
}

# =============================================================================
# NOTIFICATION COMPLÈTE
# =============================================================================

main() {
    log "INFO" "=========================================="
    log "INFO" "DEBUT: Notification de déploiement"
    log "INFO" "Statut: $BUILD_STATUS"
    log "INFO" "Environnement: $ENVIRONMENT"
    log "INFO" "Projet: $PROJECT"
    log "INFO" "Version: $VERSION"
    log "INFO" "=========================================="
    
    local errors=0
    
    # 1. Notification Slack
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        if ! send_slack_notification "$SLACK_WEBHOOK_URL" "$SLACK_CHANNEL"; then
            errors=$((errors + 1))
        fi
    fi
    
    # 2. Notification Email
    if [ -n "$EMAIL_RECIPIENTS" ]; then
        if ! send_email_notification "$EMAIL_RECIPIENTS"; then
            errors=$((errors + 1))
        fi
    fi
    
    # 3. Notification MS Teams (optionnel)
    if [ -n "${MS_TEAMS_WEBHOOK:-}" ]; then
        if ! send_teams_notification "$MS_TEAMS_WEBHOOK"; then
            errors=$((errors + 1))
        fi
    fi
    
    # 4. Notification Discord (optionnel)
    if [ -n "${DISCORD_WEBHOOK:-}" ]; then
        if ! send_discord_notification "$DISCORD_WEBHOOK"; then
            errors=$((errors + 1))
        fi
    fi
    
    # 5. Notification Système
    if ! send_system_notification; then
        errors=$((errors + 1))
    fi
    
    log "INFO" "=========================================="
    
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "Toutes les notifications envoyées avec succès"
    else
        log "ERROR" "$errors notification(s) ont échoué"
    fi
    
    log "INFO" "FIN: Notification de déploiement"
    log "INFO" "=========================================="
    
    # Toujours retourner 0 car ce n'est pas bloquant
    exit 0
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Afficher l'aide si pas d'arguments
if [ "$#" -eq 0 ] && [ -z "$BUILD_STATUS" ]; then
    echo "Usage: $0 [status] [environment] [project] [version]"
    echo ""
    echo "Arguments:"
    echo "  status       Statut du build (SUCCESS, FAILURE, UNSTABLE, ABORTED)"
    echo "  environment  Environnement de déploiement (dev, preprod, prod)"
    echo "  project      Nom du projet (deploymatic, tfsimon)"
    echo "  version      Version déployée"
    echo ""
    echo "Variables d'environnement:"
    echo "  BUILD_STATUS      Statut du build"
    echo "  ENVIRONMENT       Environnement"
    echo "  PROJECT           Projet"
    echo "  VERSION           Version"
    echo "  BUILD_NUMBER      Numéro de build"
    echo "  BUILD_URL         URL du build"
    echo "  SLACK_WEBHOOK_URL Webhook URL pour Slack"
    echo "  EMAIL_RECIPIENTS  Destinataires email"
    echo ""
    echo "Exemple:"
    echo "  ./notify.sh SUCCESS dev deploymatic 4.0.9"
    echo "  ou via Jenkins: BUILD_STATUS=SUCCESS ENVIRONMENT=dev ./notify.sh"
    exit 0
fi

# Exécution principale
main "$@"
