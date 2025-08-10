#!/bin/bash
echo "Instalando k3s con configuración optimizada..."

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="
  --disable traefik 
  --disable servicelb 
  --disable metrics-server 
  --disable local-storage
  --write-kubeconfig-mode 644
" sh -

mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config



echo "k3s instalado correctamente"
echo "Test: kubectl get nodes"
echo "Para crear un namespace demo"
echo "kubectl create namespace demo-app"