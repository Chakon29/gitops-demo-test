#!/bin/bash

echo "Instalando ArgoCD Image Updater - Version Corregida y Funcional..."

# 1. LIMPIAR INSTALACIÓN ANTERIOR SI EXISTE
echo "Limpiando instalación anterior..."
kubectl delete deployment argocd-image-updater -n argocd --ignore-not-found=true
kubectl delete configmap argocd-image-updater-config -n argocd --ignore-not-found=true
kubectl delete serviceaccount argocd-image-updater -n argocd --ignore-not-found=true
kubectl delete clusterrole argocd-image-updater --ignore-not-found=true
kubectl delete clusterrolebinding argocd-image-updater --ignore-not-found=true

# 2. CONFIGURAR SECRET PARA GITHUB CONTAINER REGISTRY
echo "Configurando acceso a GitHub Container Registry..."
echo "IMPORTANTE: Necesitas un Personal Access Token (PAT) de GitHub con permisos 'read:packages'."
echo ""

read -p "Ingresa tu GitHub Personal Access Token: " GITHUB_PAT
read -p "Ingresa tu email de GitHub: " GITHUB_EMAIL

if [ -z "$GITHUB_PAT" ] || [ -z "$GITHUB_EMAIL" ]; then
    echo "ERROR: GitHub PAT y email son requeridos"
    exit 1
fi

echo "Creando secret para GitHub Container Registry..."
# Borramos el secreto en ambos namespaces por si acaso
kubectl delete secret ghcr-secret -n demo-app --ignore-not-found=true
kubectl delete secret ghcr-secret -n argocd --ignore-not-found=true

# --- LA CORRECCIÓN CLAVE ESTÁ AQUÍ ---
# Creamos el secreto en el namespace 'argocd' para que el Image Updater lo pueda leer.
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=Chakon29 \
  --docker-password="$GITHUB_PAT" \
  --docker-email="$GITHUB_EMAIL" \
  --namespace=argocd

# 3. INSTALAR ARGOCD IMAGE UPDATER (RBAC)
echo "Instalando RBAC para ArgoCD Image Updater..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-image-updater
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-image-updater
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["argoproj.io"]
  resources: ["applications"]
  verbs: ["get", "list", "watch", "update", "patch"] # Se añaden permisos de update/patch
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-image-updater
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-image-updater
subjects:
- kind: ServiceAccount
  name: argocd-image-updater
  namespace: argocd
EOF

# 4. CREAR CONFIGMAP APUNTANDO AL SECRETO CORRECTO
echo "Creando configuración del Image Updater..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
    - name: ghcr.io
      api_url: https://ghcr.io
      prefix: ghcr.io
      ping: true
      # --- CORRECCIÓN CLAVE ---
      # Apuntamos al secreto en el namespace 'argocd'
      credentials: pullsecret:argocd/ghcr-secret
      default: true
EOF

# 5. DEPLOYMENT DEL IMAGE UPDATER
echo "Creando deployment de ArgoCD Image Updater..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-image-updater
  namespace: argocd
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-image-updater
  template:
    metadata:
      labels:
        app.kubernetes.io/name: argocd-image-updater
    spec:
      serviceAccountName: argocd-image-updater
      containers:
      - name: argocd-image-updater
        image: quay.io/argoproj/argocd-image-updater:v0.12.0 # Usar una versión específica es buena práctica
        command:
        - /usr/local/bin/argocd-image-updater
        - run
        - --interval=2m
        - --log-level=info
        ports:
        - containerPort: 8080
          name: health
        volumeMounts:
        - name: image-updater-conf
          mountPath: /app/config
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: image-updater-conf
        configMap:
          name: argocd-image-updater-config
EOF

# 6. ESPERAR QUE ESTÉ LISTO
echo "Esperando ArgoCD Image Updater..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-image-updater -n argocd

# 7. VERIFICAR INSTALACIÓN
echo "Verificando instalación..."
sleep 10

if kubectl get pods -n argocd | grep argocd-image-updater | grep Running > /dev/null; then
    echo "SUCCESS: ArgoCD Image Updater instalado correctamente."
    echo "El sistema ahora buscará nuevas imágenes cada 2 minutos y las desplegará automáticamente."
else
    echo "ERROR: Fallo en la instalación de ArgoCD Image Updater."
    kubectl logs -n argocd deployment/argocd-image-updater --tail=50
fi