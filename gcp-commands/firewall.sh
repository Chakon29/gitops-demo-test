# Regla completa para GitOps con capacidad de escalamiento
gcloud compute firewall-rules create gitops-stack-complete \
    --allow tcp:22,tcp:80,tcp:443,tcp:3000,tcp:6443,tcp:8080,tcp:9090,tcp:30000-30999,tcp:30203,tcp:30204 \
    --source-ranges 0.0.0.0/0 \
    --target-tags gitops-stack \
    --description="GitOps complete stack - ArgoCD, Prometheus, Grafana, K8s API, and scalable NodePorts" \
    --priority 1000