#!/bin/bash
set -euo pipefail

# ===== Couleurs =====
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# ===== Fonctions Log =====
log() { echo -e "${BLUE}==>${RESET} $1"; }
success() { echo -e "${GREEN}✔${RESET} $1"; }
error_exit() { echo -e "${RED}✖${RESET} $1"; exit 1; }

require_whiptail() {
  command -v whiptail >/dev/null 2>&1 || apt install -y whiptail
}

# ===== Variables par défaut =====
CTID=900
HOSTNAME="forgejo"
DISK=8
RAM=1024
STORAGE="local-lvm"
IPADDR=""
GATEWAY="192.168.1.1"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

show_menu() {
  require_whiptail
  whiptail --title "Forgejo LXC Installer (Docker Edition)" \
    --menu "Choisissez un mode de déploiement :" 15 60 2 \
    "1" "🟢 Mode Standard (valeurs par défaut, zéro question)" \
    "2" "🔵 Mode Avancé (personnalisation complète)" 3>&1 1>&2 2>&3
}

ask_for_parameters() {
  read -p "ID du conteneur [900] : " input && CTID="${input:-$CTID}"
  read -p "Nom d'hôte [forgejo] : " input && HOSTNAME="${input:-$HOSTNAME}"
  read -p "Taille du disque (Go) [8] : " input && DISK="${input:-$DISK}"
  read -p "RAM (Mo) [1024] : " input && RAM="${input:-$RAM}"
  read -p "Stockage [local-lvm] : " input && STORAGE="${input:-$STORAGE}"
  read -p "Adresse IP (laisser vide pour DHCP) : " IPADDR
  if [ -n "$IPADDR" ]; then
    read -p "Passerelle [192.168.1.1] : " input && GATEWAY="${input:-$GATEWAY}"
  fi
}

check_template() {
  if [ ! -f "$TEMPLATE_PATH" ]; then
    log "📦 Téléchargement du template Ubuntu 22.04..."
    pveam update
    pveam download local $TEMPLATE || error_exit "Échec du téléchargement du template"
  fi
}

create_container() {
  log "⚙️ Création du conteneur $CTID..."

  if [ -z "$IPADDR" ]; then
    NET="name=eth0,bridge=vmbr0,ip=dhcp"
  else
    NET="name=eth0,bridge=vmbr0,ip=$IPADDR/24,gw=$GATEWAY"
  fi

  pct create "$CTID" local:vztmpl/$TEMPLATE -hostname "$HOSTNAME" \
    -memory "$RAM" -cores 2 -net0 "$NET" -ostype ubuntu \
    -rootfs "$STORAGE:$DISK" -features nesting=1 || error_exit "Échec création CT"

  pct start "$CTID" || error_exit "Échec démarrage CT"
  success "Conteneur $CTID lancé"
}

exec_in_ct() {
  pct exec "$CTID" -- bash -euxc "$1" || error_exit "Échec d'exécution dans le CT : $1"
}

install_packages_in_ct() {
  log "📦 Installation de Docker & outils dans le conteneur..."
  exec_in_ct "apt update && apt install -y curl gnupg2 ca-certificates lsb-release software-properties-common jq git"
}

install_docker_in_ct() {
  exec_in_ct "
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
  "
  success "Docker installé dans le CT"
}

install_docker_compose_in_ct() {
  exec_in_ct "
    curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  "
  success "Docker Compose installé"
}

deploy_forgejo_in_ct() {
  log "🚀 Déploiement de Forgejo (Docker)..."
  pct exec "$CTID" -- bash -c "
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
  " || error_exit "Échec du déploiement Forgejo"
  success "Forgejo lancé"
}

show_summary() {
  CT_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
  echo -e "\n${GREEN}✔ Installation terminée !${RESET}"
  echo -e "🌍 Accès Web : ${BLUE}http://$CT_IP:3000${RESET}"
  echo -e "🔐 SSH Git : ${BLUE}ssh://git@$CT_IP:2222${RESET}\n"
}

# ========== MAIN ==========
MODE=$(show_menu)
[ "$MODE" = "2" ] && ask_for_parameters || log "✅ Mode Standard sélectionné"

check_template
create_container
install_packages_in_ct
install_docker_in_ct
install_docker_compose_in_ct
deploy_forgejo_in_ct
show_summary
