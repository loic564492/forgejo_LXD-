#!/bin/bash

set -e

echo -e "\n=== Création d'un conteneur LXC avec Forgejo (Ubuntu 22.04 + Docker) ===\n"

# Choix des paramètres utilisateur
read -p "ID du conteneur (ex: 900) : " CTID
read -p "Nom d'hôte (ex: forgejo) : " HOSTNAME
read -p "Taille du disque (en Go, ex: 8) : " DISK
read -p "RAM (en Mo, ex: 512) : " RAM
read -p "Stockage (ex: local-lvm) : " STORAGE
read -p "Adresse IP (laisser vide pour DHCP) : " IPADDR

# Template Ubuntu 22.04
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

# Téléchargement du template si absent
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "Téléchargement du template Ubuntu 22.04..."
  pveam update
  pveam download local $TEMPLATE
fi

# Construction de la ligne réseau
if [ -z "$IPADDR" ]; then
  NET="name=eth0,bridge=vmbr0,ip=dhcp"
else
  NET="name=eth0,bridge=vmbr0,ip=$IPADDR/24,gw=192.168.1.1"
fi

# Création du conteneur
echo "Création du CT $CTID..."
pct create $CTID local:vztmpl/$TEMPLATE -hostname $HOSTNAME \
  -memory $RAM -cores 2 -net0 $NET -ostype ubuntu \
  -rootfs $STORAGE:$DISK \
  -features nesting=1

# Démarrage du CT
pct start $CTID
sleep 5

# Installation des paquets nécessaires
echo "Installation de Docker et des outils dans le CT..."
pct exec $CTID -- bash -c "
  apt update &&
  apt install -y curl gnupg2 ca-certificates lsb-release software-properties-common jq git
"

# Ajout du dépôt Docker
pct exec $CTID -- bash -c "
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&
  echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable' > /etc/apt/sources.list.d/docker.list &&
  apt update &&
  apt install -y docker-ce docker-ce-cli containerd.io
"

# Installation de Docker Compose
pct exec $CTID -- bash -c "
  curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose &&
  chmod +x /usr/local/bin/docker-compose
"

# Création de l’arborescence Forgejo + docker-compose.yml
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

# Démarrage de Forgejo
pct exec $CTID -- bash -c "cd /opt/forgejo && docker-compose up -d"

echo -e "\nForgejo est installé et accessible sur le port 3000 de l'IP du conteneur."
