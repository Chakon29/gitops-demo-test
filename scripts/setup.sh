#!/bin/bash

echo "📝 Actualizando repositorio con configuraciones corregidas"
echo "========================================================="

# Actualizar deployment del backend con imagen correcta
echo "🔧 Actualizando environments/dev/backend-go-api/deployment.yaml..."

cat > environments/dev/backend-go-api/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-go-api
  namespace: demo-app
  labels:
    app: backend-go-api
    tier: backend
    version: "1.0.0"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend-go-api
  template:
    metadata:
      labels:
        app: backend-go-api
        tier: backend
        version: "1.0.0"
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      imagePullSecrets:
      - name: ghcr-secret
      containers:
      - name: backend-api
        image: ghcr.io/chakon29/backend-go-api:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: PORT
          value: "8080"
        - name: VERSION
          value: "GitOps-v1.0.0-AUTO"
        - name: ENV
          value: "development"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "300m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 10
---
apiVersion: v1
kind: Service
metadata:
  name: backend-go-api-service
  namespace: demo-app
  labels:
    app: backend-go-api
    tier: backend
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30203
    name: http
  selector:
    app: backend-go-api
EOF

# Actualizar aplicación ArgoCD con annotations correctas
echo "🔧 Actualizando argocd-applications/backend-go-api-app.yaml..."

cat > argocd-applications/backend-go-api-app.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backend-go-api-dev
  namespace: argocd
  labels:
    environment: dev
    app: backend-go-api
    tier: backend
  annotations:
    # ArgoCD Image Updater annotations - CORREGIDAS
    argocd-image-updater.argoproj.io/image-list: backend=ghcr.io/chakon29/backend-go-api
    argocd-image-updater.argoproj.io/backend.update-strategy: latest
    argocd-image-updater.argoproj.io/backend.allow-tags: regexp:^(latest|sha-[0-9a-f]{7})$
    argocd-image-updater.argoproj.io/backend.pull-secret: pullsecret:demo-app/ghcr-secret
    argocd-image-updater.argoproj.io/write-back-method: git
spec:
  project: default
  
  # SOURCE: Apunta a la estructura correcta
  source:
    repoURL: https://github.com/Chakon29/gitops-demo-test
    targetRevision: main
    path: environments/dev/backend-go-api
  
  # DESTINATION: Donde se despliega
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-app
  
  # SYNC POLICY: Automático para desarrollo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    
  # HEALTH CHECKS
  ignoreDifferences: []
  revisionHistoryLimit: 10
EOF

# Crear script de configuración completa
echo "🔧 Creando scripts/complete-gitops-setup.sh..."

mkdir -p scripts

cat > scripts/complete-gitops-setup.sh <<'EOF'
#!/bin/bash

echo "🚀 GitOps Complete Setup - Configuración desde Cero"
echo "=================================================="

# Verificar prerequisites
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ ERROR: kubectl no configurado. Verifica tu cluster k3s"
    exit 1
fi

# Solicitar GitHub PAT
echo "🔐 Configuración de GitHub Container Registry"
echo "Necesitas un GitHub Personal Access Token con permisos:"
echo "  - read:packages"
echo "  - write:packages"
echo ""
read -p "Ingresa tu GitHub PAT: " GITHUB_PAT

if [ -z "$GITHUB_PAT" ]; then
    echo "❌ ERROR: GitHub PAT requerido"
    exit 1
fi

export GITHUB_PAT="$GITHUB_PAT"

# Instalar ArgoCD
echo "📦 Instalando ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30080,"name":"http"}]}}'

# Obtener password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Instalar monitoring
echo "📊 Instalando Prometheus..."
kubectl create namespace monitoring
kubectl apply -f infrastructure/monitoring/prometheus-rbac.yaml
kubectl apply -f infrastructure/monitoring/prometheus-config.yaml
kubectl apply -f infrastructure/monitoring/prometheus-deployment.yaml
kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring

# Configurar pull secrets
echo "🔐 Configurando GHCR access..."
kubectl create namespace demo-app
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=chakon29 \
  --docker-password="$GITHUB_PAT" \
  --docker-email="vce923@gmail.com" \
  --namespace=demo-app

# Instalar ArgoCD Image Updater con configuración corregida
echo "🔄 Configurando ArgoCD Image Updater..."
kubectl apply -f infrastructure/argocd/image-updater-rbac.yaml
kubectl apply -f infrastructure/argocd/image-updater-config.yaml
kubectl apply -f infrastructure/argocd/image-updater-deployment.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-image-updater -n argocd

# Desplegar aplicaciones
echo "📱 Desplegando aplicaciones..."
kubectl apply -f argocd-applications/

echo "🎉 INSTALACIÓN COMPLETADA"
echo "========================"
echo "ArgoCD UI: http://$(curl -s ifconfig.me):30080"
echo "Usuario: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo "Prometheus: http://$(curl -s ifconfig.me):30900"
EOF

chmod +x scripts/complete-gitops-setup.sh

# Crear archivos de configuración individual para ArgoCD Image Updater
echo "🔧 Creando infrastructure/argocd/image-updater-config.yaml..."

mkdir -p infrastructure/argocd

cat > infrastructure/argocd/image-updater-config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
    - name: GitHub Container Registry
      api_url: https://ghcr.io
      prefix: ghcr.io
      ping: true
      credentials: pullsecret:demo-app/ghcr-secret
      default: false
      tagsortmode: latest-first
  log.level: info
EOF

cat > infrastructure/argocd/image-updater-rbac.yaml <<'EOF'
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

cat > infrastructure/argocd/image-updater-deployment.yaml <<'EOF'
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

echo "✅ Archivos actualizados correctamente"
echo ""
echo "📋 Archivos modificados/creados:"
echo "  - environments/dev/backend-go-api/deployment.yaml (imagen corregida + pull secret)"
echo "  - argocd-applications/backend-go-api-app.yaml (annotations corregidas)"
echo "  - scripts/complete-gitops-setup.sh (setup completo)"
echo "  - infrastructure/argocd/image-updater-*.yaml (configuración corregida)"
echo ""
echo "🚀 Próximos pasos:"
echo "1. Ejecutar ./cleanup-complete.sh"
echo "2. Ejecutar ./scripts/complete-gitops-setup.sh"
echo "3. Commitear y pushear estos cambios al repositorio"
EOF

chmod +x update_repo_script.sh

echo "✅ Scripts creados correctamente"
echo ""
echo "📋 Próximos pasos:"
echo "1. ./cleanup-complete.sh     # Limpiar VM"
echo "2. ./update_repo_script.sh   # Actualizar archivos"
echo "3. ./scripts/complete-gitops-setup.sh  # Setup completo"