#!/bin/bash

set -euo pipefail

# ===== Couleurs =====
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# ===== Fonctions =====

log() {
  echo -e "${BLUE}==>${RESET} $1"
}

success() {
  echo -e "${GREEN}✔${RESET} $1"
}

error() {
  echo -e "${RED}✖${RESET} $1"
  exit 1
}

require_whiptail() {
  command -v whiptail >/dev/null 2>&1 || apt install -y whiptail
}

show_menu() {
  require_whiptail
  whiptail --title "Forgejo LXC Installer (Docker Edition)" \
    --menu "Choisissez un mode de déploiement :" 15 60 2 \
    "1" "🟢 Mode Standard (valeurs par défaut, zéro question)" \
    "2" "🔵 Mode Avancé (personnalisation complète)" 3>&1 1>&2 2>&3
}

create_ct() {
  log "Création du conteneur LXC..."

  local NET_CONFIG

  if [ -z "$IPADDR" ]; then
    NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
  else
    NET_CONFIG="name=eth0,bridge=vmbr0,ip=${IPADDR}/24,gw=${GATEWAY}"
  fi

  pct create "$CTID" local:vztmpl/$TEMPLATE -hostname "$HOSTNAME" \
    -memory "$RAM" -cores 2 -net0 "$NET_CONFIG" -ostype ubuntu \
    -rootfs "$STORAGE:$DISK" \
    -features nesting=1 || error "Échec de création du CT"

  pct start "$CTID"
  sleep 5
  success "Conteneur $CTID démarré"
}

install_docker_stack() {
  log "Installation de Docker et Docker Compose dans le conteneur..."

  pct exec $CTID -- bash -c "
    apt update &&
    apt install -y curl gnupg2 ca-certificates lsb-release software-properties-common jq git
  "

  pct exec $CTID -- bash -c "
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&
    echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \\\$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list &&
    apt update &&
    apt install -y docker-ce docker-ce-cli containerd.io
  "

  pct exec $CTID -- bash -c "
    curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose &&
    chmod +x /usr/local/bin/docker-compose
  "

  success "Docker et Docker Compose installés dans le conteneur"
}

deploy_forgejo() {
  log "Déploiement de Forgejo via Docker..."

  pct exec $CTID -- bash -c "
    mkdir -p /opt/forgejo &&
    cat > /opt/forgejo/docker-compose.yml <<EOF
version: '3.8'
services:
  forgejo:
    image: codeberg.org/forgejo/forgejo:latest
    container_name: forgejo
    restart: always
    ports:
      - '3000:3000'
      - '2222:22'
    volumes:
      - forgejo-data:/data

volumes:
  forgejo-data:
EOF
    cd /opt/forgejo && docker-compose up -d
  "

  success "Forgejo déployé et lancé"
}

show_summary() {
  CT_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
  echo -e "\n${GREEN}✔ Installation terminée !${RESET}"
  echo -e "🌍 Accès Web : ${BLUE}http://$CT_IP:3000${RESET}"
  echo -e "🔐 SSH Git : ${BLUE}ssh://git@$CT_IP:2222${RESET}\n"
}

# ===== Début script principal =====

TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

# Téléchargement si besoin
if [ ! -f "$TEMPLATE_PATH" ]; then
  log "Téléchargement du template Ubuntu 22.04..."
  pveam update
  pveam download local $TEMPLATE || error "Échec du téléchargement du template"
fi

# Valeurs par défaut
CTID=900
HOSTNAME="forgejo"
DISK=8
RAM=1024
STORAGE="local-lvm"
IPADDR=""
GATEWAY="192.168.1.1"

MODE=$(show_menu)

if [ "$MODE" = "2" ]; then
  read -p "ID du conteneur [900] : " input && CTID="${input:-$CTID}"
  read -p "Nom d'hôte [forgejo] : " input && HOSTNAME="${input:-$HOSTNAME}"
  read -p "Taille du disque (Go) [8] : " input && DISK="${input:-$DISK}"
  read -p "RAM (Mo) [1024] : " input && RAM="${input:-$RAM}"
  read -p "Stockage [local-lvm] : " input && STORAGE="${input:-$STORAGE}"
  read -p "Adresse IP (laisser vide pour DHCP) : " IPADDR
  if [ -n "$IPADDR" ]; then
    read -p "Passerelle [192.168.1.1] : " input && GATEWAY="${input:-$GATEWAY}"
  fi
else
  log "Mode Standard sélectionné, tout se fait en automatique..."
fi

# Exécution
create_ct
install_docker_stack
deploy_forgejo
show_summary
