#!/bin/bash

echo "Instalando ArgoCD Image Updater - Version Corregida..."

# Verificar que ArgoCD esté funcionando
if ! kubectl get ns argocd &> /dev/null; then
    echo "ERROR: ArgoCD namespace no encontrado. Instala ArgoCD primero."
    exit 1
fi

# 1. LIMPIAR INSTALACIÓN ANTERIOR SI EXISTE
echo "Limpiando instalación anterior..."
kubectl delete deployment argocd-image-updater -n argocd --ignore-not-found=true
kubectl delete configmap argocd-image-updater-config -n argocd --ignore-not-found=true
kubectl delete serviceaccount argocd-image-updater -n argocd --ignore-not-found=true
kubectl delete clusterrole argocd-image-updater --ignore-not-found=true
kubectl delete clusterrolebinding argocd-image-updater --ignore-not-found=true

# 2. CONFIGURAR SECRET PARA GITHUB CONTAINER REGISTRY
echo "Configurando acceso a GitHub Container Registry..."

echo "IMPORTANTE: Necesitas crear un Personal Access Token (PAT) en GitHub"
echo "1. Ve a GitHub -> Settings -> Developer settings -> Personal access tokens"
echo "2. Crea token con permisos: read:packages, write:packages"
echo ""

read -p "Ingresa tu GitHub Personal Access Token: " GITHUB_PAT
read -p "Ingresa tu email de GitHub: " GITHUB_EMAIL

if [ -z "$GITHUB_PAT" ] || [ -z "$GITHUB_EMAIL" ]; then
    echo "ERROR: GitHub PAT y email son requeridos"
    exit 1
fi

echo "Creando secret para GitHub Container Registry..."
kubectl delete secret ghcr-secret -n demo-app --ignore-not-found=true
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=Chakon29 \
  --docker-password="$GITHUB_PAT" \
  --docker-email="$GITHUB_EMAIL" \
  --namespace=demo-app

# 3. INSTALAR ARGOCD IMAGE UPDATER DESDE CERO
echo "Instalando ArgoCD Image Updater..."

# ServiceAccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-image-updater
  namespace: argocd
EOF

# ClusterRole
kubectl apply -f - <<EOF
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
  verbs: ["get", "list", "watch", "patch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create"]
EOF

# ClusterRoleBinding
kubectl apply -f - <<EOF
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

# 4. CREAR CONFIGMAP SIMPLIFICADO
echo "Creando configuración simplificada..."
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
      credentials: pullsecret:demo-app/ghcr-secret
      default: true
EOF

# 5. DEPLOYMENT SIMPLIFICADO
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
        image: quay.io/argoproj/argocd-image-updater:latest
        command:
        - /usr/local/bin/argocd-image-updater
        - run
        - --interval=2m
        - --health-port=8080
        - --registries-conf-path=/app/config/registries.conf
        - --log-level=info
        - --argocd-server-addr=argocd-server.argocd.svc.cluster.local:443
        - --argocd-insecure=false
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
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
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
    echo "SUCCESS: ArgoCD Image Updater instalado correctamente"
    echo ""
    echo "PROXIMOS PASOS:"
    echo "1. Aplica el deployment del backend: kubectl apply -f environments/dev/backend-go-api/deployment.yaml"
    echo "2. Aplica la aplicación ArgoCD: kubectl apply -f argocd-applications/backend-api-go-app-updated.yaml"
    echo "3. El CI/CD sera completamente automatico"
    echo ""
    echo "VERIFICACION:"
    echo "kubectl logs -f deployment/argocd-image-updater -n argocd"
    echo "kubectl get applications -n argocd"
    echo ""
    echo "Ver logs ahora? (y/n)"
    read -p "Respuesta: " SHOW_LOGS
    if [[ "$SHOW_LOGS" == "y" || "$SHOW_LOGS" == "Y" ]]; then
        kubectl logs deployment/argocd-image-updater -n argocd --tail=20
    fi
else
    echo "ERROR: Fallo en instalacion de ArgoCD Image Updater"
    echo "Logs del pod:"
    kubectl logs -n argocd deployment/argocd-image-updater --tail=20
    echo ""
    echo "Estado del deployment:"
    kubectl get deployment argocd-image-updater -n argocd
    echo ""
    echo "Pods:"
    kubectl get pods -n argocd | grep argocd-image-updater
    exit 1
fi