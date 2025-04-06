# 🚀 Déploiement automatique de Forgejo dans un conteneur LXC (Ubuntu 22.04)

Ce script permet de créer automatiquement un conteneur LXC dans Proxmox, d’y installer Docker + Docker Compose, et de déployer Forgejo via Docker.

> Inspiré du style Tteck.eth : interactif, propre.

---

## 🧰 Prérequis

- Un serveur **Proxmox VE** fonctionnel
- Le template `ubuntu-22.04-standard` disponible
- Connexion internet sur le node Proxmox
- Stockage `local-lvm` (ou autre)
- Lancement du script **depuis le node Proxmox**

---

## 🧪 Lancer l'installation

Depuis le **node Proxmox**, exécutez :

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/loic564492/forgejo_LXD-/main/deploy.sh)
