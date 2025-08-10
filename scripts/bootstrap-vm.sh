#!/bin/bash

echo "Bootstrap VM para GitOps..."

# System update
apt update && apt upgrade -y

# Instalar dependencias
apt install -y gnupg lsb-release ca-certificates curl

# Docker via snap
snap install docker
groupadd docker 2>/dev/null || true
usermod -aG docker $USER

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
snap install helm --classic

# k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb --disable metrics-server --disable local-storage --write-kubeconfig-mode 644" sh -

# Configurar kubeconfig
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chown $USER:$USER ~/.kube/config

echo "VM configurada para GitOps"
echo "Siguiente: ejecutar infrastructure/argocd/install-argocd.sh"