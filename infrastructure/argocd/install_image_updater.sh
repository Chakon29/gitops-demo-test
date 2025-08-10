#!/bin/bash

echo "Instalando ArgoCD Image Updater..."

# Verificar que ArgoCD esté funcionando
if ! kubectl get ns argocd &> /dev/null; then
    echo "ERROR: ArgoCD namespace no encontrado. Instala ArgoCD primero."
    exit 1
fi

# 1. INSTALAR ARGOCD IMAGE UPDATER
echo "Instalando ArgoCD Image Updater..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

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
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=Chakon29 \
  --docker-password="$GITHUB_PAT" \
  --docker-email="$GITHUB_EMAIL" \
  --namespace=demo-app

# 3. CONFIGURAR RBAC PARA IMAGE UPDATER
echo "Configurando RBAC para Image Updater..."
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
  verbs: ["get", "list", "watch", "patch"]
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

# 4. CONFIGURAR IMAGE UPDATER CONFIG
echo "Configurando ArgoCD Image Updater..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-image-updater-config
    app.kubernetes.io/part-of: argocd-image-updater
data:
  registries.conf: |
    registries:
    - name: ghcr.io
      api_url: https://ghcr.io
      prefix: ghcr.io
      ping: true
      credentials: pullsecret:demo-app/ghcr-secret
      default: true
  git.auth: |
    # Git authentication configuration
    type: git
    username: git
    password: \${GITHUB_TOKEN}
  log.level: info
  argocd.grpc_web: true
  argocd.server_addr: argocd-server.argocd.svc.cluster.local:443
  argocd.insecure: false
  argocd.plaintext: false
EOF

# 5. PATCH DEPLOYMENT PARA USAR LA CONFIGURACIÓN
echo "Actualizando deployment de Image Updater..."
kubectl patch deployment argocd-image-updater -n argocd -p '
{
  "spec": {
    "template": {
      "spec": {
        "serviceAccountName": "argocd-image-updater",
        "containers": [
          {
            "name": "argocd-image-updater",
            "command": ["/usr/local/bin/argocd-image-updater"],
            "args": [
              "run",
              "--interval", "2m",
              "--health-port", "8080",
              "--registries-conf-path", "/app/config/registries.conf",
              "--log-level", "info",
              "--argocd-server-addr", "argocd-server.argocd.svc.cluster.local:443",
              "--argocd-insecure=false"
            ],
            "volumeMounts": [
              {
                "name": "image-updater-conf",
                "mountPath": "/app/config"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "image-updater-conf",
            "configMap": {
              "name": "argocd-image-updater-config"
            }
          }
        ]
      }
    }
  }
}'

# 6. ESPERAR QUE ESTÉ LISTO
echo "Esperando ArgoCD Image Updater..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-image-updater -n argocd

if kubectl get pods -n argocd | grep argocd-image-updater | grep Running > /dev/null; then
    echo "SUCCESS: ArgoCD Image Updater instalado correctamente"
    echo ""
    echo "PROXIMOS PASOS:"
    echo "1. Aplica tu aplicación backend: kubectl apply -f argocd-applications/backend-api-go-app-updated.yaml"
    echo "2. Verifica el deployment: kubectl apply -f environments/dev/backend-go-api/deployment.yaml"
    echo "3. El CI/CD sera completamente automatico"
    echo ""
    echo "VERIFICACION:"
    echo "kubectl logs -f deployment/argocd-image-updater -n argocd"
    echo "kubectl get applications -n argocd"
else
    echo "ERROR: Fallo en instalacion de ArgoCD Image Updater"
    kubectl logs -n argocd deployment/argocd-image-updater --tail=20
    exit 1
fi