#!/bin/bash

echo "Instalando ArgoCD Image Updater - Version Corregida y Funcional..."

# 1. LIMPIAR INSTALACIÓN ANTERIOR SI EXISTE
echo "Limpiando instalación anterior..."
kubectl delete deployment argocd-image-updater -n argocd --ignore-not-found=true
kubectl delete configmap argocd-image-updater-config -n argocd --ignore-not-found=true
kubectl delete serviceaccount argocd-image-updater -n argocd --ignore-not-found=true
kubectl delete clusterrole argocd-image-updater --ignore-not-found=true
kubectl delete clusterrolebinding argocd-image-updater --ignore-not-found=true

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

echo "Instalación completada."