#!/bin/bash

# V6

set -e

# Vérifie si whiptail est dispo
USE_WHIPTAIL=false
if command -v whiptail >/dev/null 2>&1; then
  USE_WHIPTAIL=true
fi

# Choix du mode via menu
if [ "$USE_WHIPTAIL" = true ]; then
  CHOICE=$(whiptail --title "Forgejo LXC Installer" --menu "Choisissez un mode de déploiement :" 15 60 2 \
    "1" "🟢 Mode Standard (tout auto, aucun prompt)" \
    "2" "🔵 Mode Avancé (personnalisation complète)" 3>&1 1>&2 2>&3)
else
  echo -e "\n=== Sélection du mode de déploiement ==="
  echo "1) Mode Standard (tout auto)"
  echo "2) Mode Avancé (interactif)"
  read -p "Votre choix [1/2] : " CHOICE
fi

# Valeurs par défaut
CTID=900
HOSTNAME="forgejo"
DISK=8
RAM=512
STORAGE="local-lvm"
IPADDR=""
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

# Mode avancé
if [ "$CHOICE" = "2" ]; then
  read -p "ID du conteneur [900] : " input && CTID="${input:-$CTID}"
  read -p "Nom d'hôte [forgejo] : " input && HOSTNAME="${input:-$HOSTNAME}"
  read -p "Taille du disque en Go [8] : " input && DISK="${input:-$DISK}"
  read -p "RAM en Mo [512] : " input && RAM="${input:-$RAM}"
  read -p "Stockage [local-lvm] : " input && STORAGE="${input:-$STORAGE}"
  read -p "Adresse IP (laisser vide pour DHCP) : " IPADDR
  [ -n "$IPADDR" ] && read -p "Passerelle (ex: 192.168.1.1) : " GATEWAY
fi

# Téléchargement template si manquant
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "📦 Téléchargement du template Ubuntu 22.04..."
  pveam update
  pveam download local $TEMPLATE
fi

# Configuration réseau
if [ -z "$IPADDR" ]; then
  NET="name=eth0,bridge=vmbr0,ip=dhcp"
else
  NET="name=eth0,bridge=vmbr0,ip=$IPADDR/24,gw=$GATEWAY"
fi

# Création CT
echo "⚙️ Création du CT $CTID ($HOSTNAME)..."
pct create $CTID local:vztmpl/$TEMPLATE -hostname $HOSTNAME \
  -memory $RAM -cores 2 -net0 $NET -ostype ubuntu \
  -rootfs $STORAGE:$DISK \
  -features nesting=1

# Démarrage
pct start $CTID
sleep 5

echo "📦 Installation de Docker et des outils dans le conteneur..."

# Base system + Docker
pct exec $CTID -- bash -c "
  apt update &&
  apt install -y curl gnupg2 ca-certificates lsb-release software-properties-common jq git
"

# Dépôt Docker – corrigé avec échappement 💥
pct exec $CTID -- bash -c "
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&
  echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \\\$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list &&
  apt update &&
  apt install -y docker-ce docker-ce-cli containerd.io
"

# Docker Compose
pct exec $CTID -- bash -c "
  curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose &&
  chmod +x /usr/local/bin/docker-compose
"

# Déploiement Forgejo
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
"

# Lancement Forgejo
pct exec $CTID -- bash -c "cd /opt/forgejo && docker-compose up -d"

# IP dynamique
CT_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo -e "\n✅ Forgejo est installé avec succès !"
echo -e "🌐 Accès Web : http://$CT_IP:3000"
echo -e "🔑 Accès SSH Git : ssh://git@$CT_IP:2222\n"
