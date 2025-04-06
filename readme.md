# Deploy Forgejo LXC - Proxmox Script

Ce script automatise le **déploiement de Forgejo** dans un **conteneur LXC sous Proxmox VE**, à la manière des scripts `tteck.eth`.

## 🚀 Fonctionnalités

- Crée un CT Ubuntu 22.04 avec les ressources définies par l'utilisateur
- Installe Docker, Docker Compose, et les dépendances nécessaires
- Déploie **Forgejo (fork communautaire de Gitea)** via Docker
- Expose Forgejo sur le port `3000` en HTTP (à sécuriser via reverse proxy si besoin)

## 📦 Déploiement rapide

Depuis votre hôte Proxmox :

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<ton-username>/<ton-repo>/main/deploy.sh)
