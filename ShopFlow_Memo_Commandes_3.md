# ShopFlow — Mémo des commandes opérationnelles

*Migration vers Kubernetes (GKE) · Docker · Helm · CI/CD · GitOps*

Aide-mémoire pour déployer, mettre à jour et opérer ShopFlow sur GKE avec ArgoCD + Helm.

---

## 🏗️ Architecture des deux repos

### Dépôt applicatif : `shopflow`
- Code backend + frontend
- Dockerfiles
- Workflows CI (.github/workflows/ci-backend.yaml, etc.)
- Bootstrap Kubernetes (namespaces, quotas, network policies)

### Dépôt GitOps : `shopflow-gitops`
- **Chart Helm** : `charts/shopflow/` (source unique de vérité)
- **Manifests ArgoCD** : `apps/argocd-*.yaml`
- **Valeurs par environnement** : `envs/staging/` et `envs/prod/`

**Règle** : Si c'est appliqué une fois à la main → repo app (bootstrap/). Si ArgoCD le surveille en continu → repo GitOps.

---

## 📋 Structure actuelle

```
shopflow/
├── backend/
├── frontend/
├── bootstrap/
│   ├── namespaces.yaml
│   ├── quotas/
│   ├── network-policies/
│   └── platform/
├── .github/workflows/
│   └── ci-backend.yaml
└── README.md

shopflow-gitops/
├── apps/
│   ├── argocd-root-app.yaml          (orchestration App-of-Apps)
│   ├── argocd-shopflow-staging.yaml  (déploie staging)
│   └── argocd-shopflow-prod.yaml     (déploie prod)
├── charts/shopflow/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml
│       ├── secret.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       └── servicemonitor.yaml
├── envs/
│   ├── staging/values-staging.yaml   (image.tag auto-mis à jour par CI)
│   └── prod/values-prod.yaml         (image.tag promu manuellement)
└── README.md
```

---

## 🔧 Valeurs clés

- **Projet GCP** : `shopflow-499020`
- **Région** : `northamerica-northeast2`
- **Artifact Registry** : `northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow`
- **Image backend** : `northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend`
- **Tag actuel (staging)** : `sha-120278a`
- **Namespaces** : `shopflow-staging`, `shopflow-prod`, `monitoring`, `argocd`
- **Dépôts GitHub** : `oderbel-DS/shopflow` et `oderbel-DS/shopflow-gitops`

---

## 🚀 Étape 1 : Prérequis (une seule fois)

### 1.1 Créer le cluster GKE
```bash
gcloud config set project shopflow-499020
gcloud config set compute/region northamerica-northeast2

gcloud container clusters create shopflow-cluster \
  --region northamerica-northeast2 \
  --num-nodes 1 --machine-type e2-standard-2 \
  --enable-autoscaling --min-nodes 1 --max-nodes 3 \
  --release-channel regular --enable-ip-alias \
  --enable-dataplane-v2

gcloud container clusters get-credentials shopflow-cluster \
  --region northamerica-northeast2
```

### 1.2 Créer les namespaces
```bash
kubectl apply -f bootstrap/namespaces.yaml
kubectl get ns --show-labels
```

### 1.3 Installer la plateforme (Ingress, Monitoring, ArgoCD)
```bash
# Ingress-NGINX
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f bootstrap/platform/values-monitoring.yaml

# ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f bootstrap/platform/values-argocd.yaml
```

### 1.4 Accéder à ArgoCD

#### Option 1 : Interface web (UI) + port-forward
```bash
# Terminal 1 : créer le tunnel
kubectl -n argocd port-forward svc/argocd-server 8080:80

# Terminal 2 : récupérer le password admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# Accès : http://localhost:8080 (user: admin / password du dessus)
```

#### Option 2 : CLI ArgoCD (en Cloud Shell)
```bash
# 1. Configurer le serveur ArgoCD (une seule fois)
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

ARGOCD_SERVER=$(kubectl -n argocd get svc argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Si pas d'LoadBalancer IP, utiliser le port-forward alternativement
# et laisser ARGOCD_SERVER=localhost:8080 (avec port-forward actif dans un autre terminal)

# 2. Se connecter
argocd login $ARGOCD_SERVER --username admin --password $ARGOCD_PASS --insecure

# 3. Vérifier
argocd app list
```

#### Option 3 : kubectl directement (sans CLI ArgoCD)
```bash
# Lister les applications ArgoCD
kubectl get applications -n argocd

# Voir le détail d'une application
kubectl -n argocd get application shopflow-staging -o yaml

# Déclencher un sync
kubectl patch application shopflow-staging -n argocd \
  -p '{"status":{"operationState":{"phase":"Running"}}}' --type merge
```

---

## 📦 Étape 2 : Flux CI/CD → Déploiement

### 2.1 Déclencher la CI (build + scan + push image)
```bash
cd shopflow
git add .
git commit -m "feat: mise à jour backend"
git push  # Cela déclenche le workflow .github/workflows/ci-backend.yaml
```

**La CI fait**:
1. Teste le code (pytest)
2. Scanne les vulnérabilités (Trivy)
3. Construit l'image Docker
4. Pousse l'image dans Artifact Registry avec un tag `sha-XXXXXXX`
5. Met à jour `shopflow-gitops/envs/staging/values-staging.yaml` avec ce tag

### 2.2 ArgoCD détecte et déploie (automatique)
- ArgoCD surveille le repo GitOps en continu.
- À chaque commit, ArgoCD recalcule les différences (drift).
- Helm rend le chart avec les values de staging.
- ArgoCD applique sur le cluster.

```bash
# Vérifier le déploiement
argocd app get shopflow-staging
kubectl -n shopflow-staging get deploy
kubectl -n shopflow-staging get pods
```

### 2.3 Vérifier l'image déployée
```bash
kubectl -n shopflow-staging get deploy -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'; echo
```

---

## 🔀 Étape 3 : Promotion vers Production

**Stratégie** : staging automatique, prod manuelle (approval).

### 3.1 Promotion d'image de staging vers prod

Quand vous êtes sûr du tag en staging (tests passés, canary réussi), promouvoir en prod:

```bash
# 1. Aller sur GitHub (web)
# 2. Créer une PR dans shopflow-gitops
# 3. Modifier envs/prod/values-prod.yaml
#    Remplacer le tag par celui de staging
# 4. Commit + PR review
# 5. Merge

# Ou en CLI :
cd shopflow-gitops
STAGING_TAG=$(grep "tag:" envs/staging/values-staging.yaml | head -1 | awk '{print $2}' | tr -d '"')
sed -i "s|tag:.*|tag: $STAGING_TAG|" envs/prod/values-prod.yaml
git add envs/prod/values-prod.yaml
git commit -m "chore(prod): promote $STAGING_TAG"
git push
```

ArgoCD détecte et déploie automatiquement en prod.

---

## 🔍 Commandes essentielles d'exploitation

### Vérifier les images disponibles
```bash
gcloud artifacts docker tags list \
  northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend \
  --sort-by=~UPDATE_TIME
```

### Vérifier l'état ArgoCD

#### Avec kubectl (recommandé, plus simple)
```bash
# Lister les applications ArgoCD
kubectl get applications -n argocd

# Voir le statut complet d'une application
kubectl -n argocd get application shopflow-staging -o yaml

# Voir les événements récents
kubectl -n argocd describe application shopflow-staging
```

#### Avec argocd CLI (si configuré)
```bash
# D'abord, configurer le serveur (voir section 1.4, Option 2)
argocd login <SERVER> --username admin --password <PASSWORD> --insecure

# Puis utiliser
argocd app list
argocd app get shopflow-staging
argocd app get shopflow-prod
argocd app sync shopflow-staging  # sync manuel si besoin
```

### Vérifier les pods/services
```bash
# Staging
kubectl -n shopflow-staging get deploy,svc,pods
kubectl -n shopflow-staging describe deploy shopflow-staging-shopflow

# Prod
kubectl -n shopflow-prod get deploy,svc,pods
```

### Logs
```bash
kubectl -n shopflow-staging logs -f deploy/shopflow-staging-shopflow
kubectl -n shopflow-prod logs -f deploy/shopflow-prod-shopflow
```

### Autoscaling
```bash
kubectl get hpa -n shopflow-staging
kubectl describe hpa shopflow-staging-shopflow -n shopflow-staging
```

---

## 🔐 Sécurité & Secrets

### Secrets GitHub (à configurer une seule fois)

Sur https://github.com/oderbel-DS/shopflow/settings/secrets/actions :

- **GCP_PROJECT** : `shopflow-499020`
- **GCP_SA_KEY** : contenu complet du fichier JSON (clé de compte de service)
- **GITOPS_PAT** : Personal Access Token GitHub (scope: repo)

### Secrets Kubernetes

Les secrets applicatifs (DB_PASSWORD, etc.) sont déclarés vides dans le chart et complétés soit :
- via External Secrets Operator (ESO) qui les fetch d'un gestionnaire externe,
- ou via CI qui les injecte dans les values en prod.

```bash
kubectl -n shopflow-staging get secret shopflow-staging-shopflow-secret
```

---

## 📝 Fichiers clés à connaître

| Fichier | Rôle |
|---------|------|
| `shopflow/.github/workflows/ci-backend.yaml` | Pipeline CI : build → scan → push → bump gitops |
| `shopflow-gitops/apps/argocd-root-app.yaml` | Entry point App-of-Apps (démarre tout) |
| `shopflow-gitops/apps/argocd-shopflow-staging.yaml` | ArgoCD Application pour staging |
| `shopflow-gitops/apps/argocd-shopflow-prod.yaml` | ArgoCD Application pour prod |
| `shopflow-gitops/charts/shopflow/Chart.yaml` | Définition du chart Helm |
| `shopflow-gitops/charts/shopflow/values.yaml` | Valeurs par défaut Helm |
| `shopflow-gitops/envs/staging/values-staging.yaml` | Surcharges staging (image.tag auto-bumped) |
| `shopflow-gitops/envs/prod/values-prod.yaml` | Surcharges prod (image.tag promu manuellement) |

---

## 🛠️ Dépannage courant

### Les pods ne démarrent pas
```bash
kubectl -n shopflow-staging describe pod <POD_NAME>
kubectl -n shopflow-staging logs <POD_NAME>
# Chercher : image inexistante, secrets manquants, ressources insuffisantes
```

### ArgoCD n'applique pas les changements
```bash
# Option 1 : avec kubectl
kubectl -n argocd patch application shopflow-staging \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}' --type merge

# Option 2 : avec argocd CLI (si configuré)
argocd app sync shopflow-staging --force  # Force un sync
argocd app refresh shopflow-staging       # Rafraîchit le cache
```

### Image ne change pas après CI
```bash
# 1. Vérifier le commit dans shopflow-gitops
git log --oneline envs/staging/values-staging.yaml

# 2. Forcer une sync ArgoCD
argocd app sync shopflow-staging

# 3. Vérifier l'image actuelle
kubectl -n shopflow-staging get deploy -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'
```

### Quota/Resources insuffisants
```bash
kubectl describe resourcequota -n shopflow-staging
kubectl top nodes
kubectl top pods -n shopflow-staging
```

---

## 📚 Références rapides

- **Artifact Registry** : https://console.cloud.google.com/artifacts
- **GKE Cluster** : https://console.cloud.google.com/kubernetes/clusters
- **GitHub Actions** : https://github.com/oderbel-DS/shopflow/actions
- **ArgoCD UI** : kubectl port-forward + http://localhost:8080
- **Kubectl cheatsheet** : https://kubernetes.io/docs/reference/kubectl/quick-reference/
