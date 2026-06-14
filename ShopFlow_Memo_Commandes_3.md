# ShopFlow — Guide opérationnel complet

**Version:** 1.0 · **Dernière mise à jour:** Juin 2026  
**Technologie Stack:** Kubernetes (GKE) · Docker · Helm · CI/CD GitHub Actions · GitOps ArgoCD

## 📖 Introduction

Ce document constitue le guide opérationnel de référence pour déployer, maintenir et opérer l'infrastructure ShopFlow sur GKE. Il couvre l'intégralité du cycle de vie : provisionnement initial, déploiement continu via CI/CD, promotion entre environnements et troubleshooting en production.

**Principes fondamentaux:**
- **Single Source of Truth** : La configuration Helm réside uniquement dans le repo GitOps
- **Infrastructure as Code** : Tous les changements sont versionnés et traçables via Git
- **Automated Reconciliation** : ArgoCD synchronise continuellement l'état du cluster avec la déclaration Git
- **Promotion Gérée** : Staging automatique, production manuelle pour garantir la qualité

---

## 🏗️ Architecture des deux repos

L'infrastructure ShopFlow suit le modèle GitOps professionnel avec séparation claire entre le code applicatif et la configuration d'infrastructure. Cette séparation garantit :
- **Traçabilité** : Chaque déploiement est lié à un commit Git spécifique
- **Auditabilité** : Tous les changements d'infrastructure sont enregistrés et reviewables
- **Reproductibilité** : La même configuration Git produit toujours le même résultat

### **Dépôt applicatif : `shopflow`**

**Rôle:** Contient le code source et les pipelines d'intégration continue  
**Responsabilité:** Build, test, scan de sécurité, publication des artefacts

Contient:
- Code backend + frontend source
- Dockerfiles pour la conteneurisation
- Workflows CI (.github/workflows/ci-backend.yaml, ci-frontend.yaml, etc.)
- Configuration bootstrap (appliquée une seule fois) : namespaces, quotas, network policies

### **Dépôt GitOps : `shopflow-gitops`**

**Rôle:** Contient la configuration déclarative de tous les déploiements (source unique de vérité)  
**Responsabilité:** Synchronisation continuée du cluster avec la déclaration Git

Contient:
- **Chart Helm** : `charts/shopflow/` (définition unique du déploiement)
- **Manifests ArgoCD** : `apps/argocd-*.yaml` (orchestration et Applications)
- **Valeurs par environnement** : `envs/staging/values-staging.yaml`, `envs/prod/values-prod.yaml`

### **Règle de séparation des responsabilités**

| Type de configuration | Repo | Fréquence |
|----------------------|------|-----------|
| Code source, tests, CI | `shopflow` | À chaque commit |
| Chart Helm, ArgoCD manifests | `shopflow-gitops` | À la mise à jour d'infrastructure |
| Bootstrap (namespaces, quotas) | `shopflow` | Une seule fois au démarrage |
| Image tags, environment overrides | `shopflow-gitops/envs/` | À chaque déploiement |

**Règle cruciale:** Si c'est appliqué une seule fois à la main et ne change jamais → `shopflow/bootstrap/`. Si ArgoCD le surveille en continu et le synchronise automatiquement → `shopflow-gitops/`.

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

## 🚀 Étape 1 : Provisionnement initial (une seule fois)

### 1.0 Comprendre le flux de provisionnement

Le provisionnement suit une séquence ordonnée pour garantir les dépendances réseau et RBAC :

1. **Cluster GKE** : Infrastructure de base (workers, control plane)
2. **Namespaces** : Isolation des workloads par environnement
3. **Plateforme** : Ingress, Monitoring, ArgoCD (composants centralisés)
4. **Applications** : ShopFlow deployments (managés par ArgoCD)

### 1.1 Prérequis

**Ressources GCP requises:**
- Projet GCP actif avec billing activé
- Cloud SDK installé (`gcloud`)
- Permissions IAM : `Kubernetes Engine Admin`, `Compute Admin`

```bash
# Vérifier la configuration GCloud
gcloud config get-value project
gcloud auth list
gcloud config list

# S'authentifier si nécessaire
gcloud auth login
gcloud config set project shopflow-499020
```

### 1.2 Créer et configurer le cluster GKE

**Objectif:** Provisionner un cluster GKE hautement disponible avec autoscaling et features de sécurité

**Considérations:**
- **Région:** `northamerica-northeast2` (conforme à l'Artifact Registry)
- **Machine type:** `e2-standard-2` (2 vCPU, 8 GB RAM) pour staging/test
- **Autoscaling:** Min 1, Max 3 nœuds (économique pour dev, scalable pour prod)
- **IP Alias:** Réseau optimisé (cluster et services sur VPC)
- **Dataplane V2:** eBPF pour networking haute performance

```bash
# 1. Initialiser la région et projet
gcloud config set project shopflow-499020
gcloud config set compute/region northamerica-northeast2

# 2. Créer le cluster (peut prendre 5-10 minutes)
gcloud container clusters create shopflow-cluster \
  --region northamerica-northeast2 \
  --num-nodes 1 \
  --machine-type e2-standard-2 \
  --enable-autoscaling --min-nodes 1 --max-nodes 3 \
  --release-channel regular \
  --enable-ip-alias \
  --enable-dataplane-v2 \
  --addons HttpLoadBalancing,HorizontalPodAutoscaling

# 3. Obtenir les credentials kubeconfig
gcloud container clusters get-credentials shopflow-cluster \
  --region northamerica-northeast2

# 4. Vérifier la connexion
kubectl cluster-info
kubectl get nodes -o wide
```

**Vérification** : Le retour doit afficher 1 nœud avec le cluster GKE et les credentials configurés localement.

### 1.3 Créer les namespaces

**Objectif:** Isoler les workloads par environnement et fonction

**Namespaces créés:**
- `shopflow-dev` : Développement et testing
- `shopflow-staging` : Pre-production (promotion du code avant prod)
- `shopflow-prod` : Production (données réelles)
- `monitoring` : Stack Prometheus/Grafana (accès cluster-wide)
- `argocd` : ArgoCD controller (accès cluster-wide)

```bash
# Appliquer les namespaces
kubectl apply -f bootstrap/namespaces.yaml

# Vérifier la création
kubectl get namespaces --show-labels

# Sortie attendue :
# NAME                STATUS   AGE   LABELS
# shopflow-dev        Active   2s    env=dev,team=shopflow
# shopflow-staging    Active   2s    env=staging,team=shopflow
# shopflow-prod       Active   2s    env=production,team=shopflow
# monitoring          Active   2s    <none>
# argocd              Active   2s    <none>
# default             Active   X     <none>
```

**Vérification détaillée:**
```bash
# Vérifier les labels pour la segmentation
kubectl get ns shopflow-prod -o jsonpath='{.metadata.labels}' | jq .

# Vérifier les quotas appliqués (si configurés)
kubectl get resourcequota -n shopflow-staging
```

### 1.4 Installer la plateforme (Ingress, Monitoring, ArgoCD)

**Objectif:** Déployer les composants centralisés supportant tous les environnements

#### 1.4.1 Ingress NGINX

**Rôle:** Router HTTP/HTTPS vers les services internes  
**Fonctionnement:** Écoute sur les ports 80/443, redirige vers ClusterIP services basé sur le hostname HTTP

```bash
# Ajouter la repository Helm NGINX
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installer l'Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Vérifier l'installation
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Récupérer l'IP publique (elle peut prendre 1-2 minutes à s'assigner)
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# Attendre que l'IP soit assignée
kubectl get svc -n ingress-nginx ingress-nginx-controller --watch
```

**Vérification:**
```bash
# L'Ingress Controller doit être en état Running
kubectl get deploy -n ingress-nginx -o wide
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=20
```

#### 1.4.2 Kube-Prometheus-Stack (Monitoring)

**Rôle:** Monitoring et alerting cluster-wide  
**Composants:** Prometheus (scrape metrics), Grafana (visualization), Alertmanager (alerting)  
**Fonctionnement:** Prometheus scrape des métriques toutes les 30s, Grafana les visualise, Alertmanager déclenche des alertes

```bash
# Ajouter la repository Prometheus Community
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

# Installer kube-prometheus-stack
helm install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f bootstrap/platform/values-monitoring.yaml

# Vérifier les composants
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Attendre que tous les pods soient Running (peut prendre 1-2 minutes)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=kps \
  -n monitoring \
  --timeout=300s
```

**Vérification:**
```bash
# Accéder à Grafana
kubectl -n monitoring port-forward svc/kps-grafana 3000:80 &

# URL: http://localhost:3000 (user: admin, password voir plus bas)
# Récupérer le password
kubectl -n monitoring get secret --sort-by='{.metadata.creationTimestamp}' -o jsonpath='{.items[-1].data.admin-password}' | base64 -d ; echo

# Vérifier les ServiceMonitors (découverte automatique des métriques)
kubectl get servicemonitor -n monitoring
kubectl get servicemonitor -A
```

#### 1.4.3 ArgoCD

**Rôle:** Orchestration GitOps et synchronisation déclarative  
**Fonctionnement:** 
1. Écoute le repo Git configuré
2. Compare l'état Git avec l'état cluster (diff)
3. Applique automatiquement ou manuellement les changements
4. Réconcilie continuellement (évite les dérives)

**Pattern App-of-Apps:** ArgoCD root orchestre les ApplicationSets pour staging et prod

```bash
# Ajouter la repository ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Installer ArgoCD
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f bootstrap/platform/values-argocd.yaml

# Attendre que les pods ArgoCD soient prêts
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=argocd \
  -n argocd \
  --timeout=300s

# Vérifier l'installation
kubectl get pods -n argocd
kubectl get svc -n argocd
```

**Vérification:**
```bash
# Le service argocd-server doit être accessible
kubectl get svc -n argocd argocd-server

# Récupérer le password admin initial
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo "ArgoCD Admin Password: $ARGOCD_PASS"
```

### 1.5 Accéder à ArgoCD UI

**Trois options selon votre contexte:**

#### Option A : Port-Forward (recommandé pour cloud shell / SSH)

**Idéal pour:** Environnement distant, accès sans configuration

```bash
# Terminal 1 : Créer le tunnel (reste actif)
kubectl -n argocd port-forward svc/argocd-server 8080:80

# Terminal 2 : Récupérer le password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# Naviguer vers : http://localhost:8080
# Credentials : admin / <password>
```

#### Option B : ArgoCD CLI (si déjà installé)

**Idéal pour:** Automation et scripting

```bash
# 1. Configurer une première fois
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

ARGOCD_SERVER=$(kubectl -n argocd get svc argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# S'il n'y a pas de LoadBalancer IP, utiliser port-forward + localhost:8080
ARGOCD_SERVER="localhost:8080"  # avec port-forward dans autre terminal

# 2. Login ArgoCD
argocd login $ARGOCD_SERVER \
  --username admin \
  --password $ARGOCD_PASS \
  --insecure

# 3. Vérifier la connexion
argocd account list
argocd app list
```

#### Option C : kubectl directement (recommandé)

**Idéal pour:** Debugging, pas de dépendance CLI externe

```bash
# Lister les applications ArgoCD
kubectl get applications -n argocd

# Voir le détail YAML d'une application
kubectl -n argocd get application shopflow-staging -o yaml

# Voir les événements récents
kubectl -n argocd describe application shopflow-staging

# Voir les ressources managées par une application
kubectl -n argocd get application shopflow-staging -o jsonpath='{.status.resources}' | jq .
```

**Vérification globale du provisionnement:**
```bash
# Vérifier que tous les composants clés sont prêts
echo "=== CLUSTER ===" && kubectl get nodes
echo -e "\n=== NAMESPACES ===" && kubectl get ns
echo -e "\n=== ARGOCD ===" && kubectl get deploy -n argocd
echo -e "\n=== INGRESS ===" && kubectl get deploy -n ingress-nginx
echo -e "\n=== MONITORING ===" && kubectl get pods -n monitoring | head -5
```

## 📦 Étape 2 : Flux CI/CD → GitOps → Déploiement

### 2.0 Comprendre le pipeline complet

**Architecture du flux :**

```
CODE (GitHub)
      ↓ git push
GITHUB ACTIONS (CI)
      ↓ build + scan + push
ARTIFACT REGISTRY (Image registrée)
      ↓ bump tag
SHOPFLOW-GITOPS Repo (values mis à jour)
      ↓ Git change detected
ARGOCD (Reconciliation)
      ↓ Helm render
KUBERNETES (Apply)
      ↓
POD RUNNING (Application)
```

**Timing:** Normalement 2-5 minutes du push au pod running

### 2.1 Déclencher la CI (Build + Test + Push)

**Objectif:** Compiler, tester, scanner et publier l'image Docker

**Prérequis:**
- Secrets GitHub configurés (GCP_PROJECT, GCP_SA_KEY, GITOPS_PAT) dans la repo `shopflow`
- Permission d'écriture dans Artifact Registry (via Service Account)
- Permission de push dans shopflow-gitops repo (via Personal Access Token)

```bash
# 1. Naviguer au repo applicatif
cd shopflow

# 2. Faire un changement au code (exemple backend)
# Modifier un fichier, e.g. backend/app/main.py

# 3. Committer et pousser
git add .
git commit -m "feat: update backend functionality"
git push origin main

# 4. Accéder à GitHub Actions pour monitorer
# https://github.com/oderbel-DS/shopflow/actions

# OU vérifier via gcloud
gcloud artifacts docker tags list \
  northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend \
  --sort-by=~UPDATE_TIME --limit=5
```

**Ce que la CI fait :**

1. **Checkout** : Clone le repo
2. **Lint & Test** : `ruff check`, `pytest` sur le code Python
3. **Build** : Construit l'image Docker depuis le Dockerfile
4. **Push** : Publie dans `northamerica-northeast2-docker.pkg.dev` avec un tag `sha-XXXXXXX` (commit SHA)
5. **Security Scan** : Trivy scanne les vulnérabilités (échoue si CRITICAL/HIGH détectées)
6. **GitOps Update** : Met à jour `shopflow-gitops/envs/staging/values-staging.yaml` avec le nouveau tag
7. **Push GitOps** : Pousse automatiquement le changement dans le repo GitOps

**Vérification du build :**
```bash
# Voir l'exécution du workflow GitHub
# Accéder à : https://github.com/oderbel-DS/shopflow/actions/workflows/ci-backend.yaml

# Vérifier l'image dans Artifact Registry
REGISTRY="northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend"

# Lister les tags récents
gcloud artifacts docker tags list $REGISTRY --sort-by=~UPDATE_TIME --limit=5

# Inspecter une image spécifique
gcloud artifacts docker describe $REGISTRY:sha-120278a

# Ou via Docker :
docker pull $REGISTRY:sha-120278a
docker image inspect $REGISTRY:sha-120278a
```

### 2.2 ArgoCD détecte et déploie automatiquement

**Objectif:** Synchroniser l'état cluster avec la déclaration Git

**Fonctionnement d'ArgoCD :**

1. **Watch Repository** : ArgoCD poll le repo GitOps toutes les 3 minutes (configurable)
2. **Template Rendering** : Helm rend les templates avec les values stage/prod
3. **Diff Calculation** : Compare l'état Git avec l'état cluster
4. **Sync Strategy** : Applique automatiquement (auto-sync) ou attend un sync manuel
5. **Monitor** : Continue de reconcilier toutes les 30 secondes

```bash
# L'application Staging a sync automatique (auto-sync enabled)
# Donc ArgoCD applique automatiquement après chaque push GitOps

# Vérifier le statut de l'application
kubectl get application -n argocd shopflow-staging
kubectl -n argocd describe application shopflow-staging

# Voir les ressources managées
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.resources}' | jq .

# Voir les changements récents (events)
kubectl -n argocd get events -n argocd --field-selector involvedObject.name=shopflow-staging
```

### 2.3 Vérifier le déploiement en staging

**Objectif:** Valider que l'application est running avec la bonne image

```bash
# 1. Vérifier l'état du déploiement
kubectl -n shopflow-staging get deploy -o wide
kubectl -n shopflow-staging get pods -o wide

# 2. Voir l'image déployée
kubectl -n shopflow-staging get deploy shopflow-staging-shopflow \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Retour attendu: northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend:sha-XXXXXXX

# 3. Vérifier les replicas (réplicas running vs desired)
kubectl -n shopflow-staging get deploy shopflow-staging-shopflow \
  -o jsonpath='{.spec.replicas} desired, {.status.readyReplicas} ready'

# 4. Voir les logs de l'application
kubectl -n shopflow-staging logs -f deploy/shopflow-staging-shopflow --all-containers=true

# 5. Vérifier les ressources du pod
kubectl -n shopflow-staging top pods -l app=shopflow-staging

# 6. Accéder à l'application (si Ingress configuré)
INGRESS_HOST=$(kubectl -n shopflow-staging get ingress -o jsonpath='{.items[0].spec.rules[0].host}')
echo "Access at: http://$INGRESS_HOST"
curl -I http://$INGRESS_HOST  # Vérifier la réponse HTTP

# 7. Vérifier les probes de santé
kubectl -n shopflow-staging get pods -o jsonpath='{.items[*].status.containerStatuses[*].ready}'

# 8. Monitoring : CPU et Memory usage
kubectl -n shopflow-staging top pods
```

**Diagnostic si les pods ne sont pas prêts :**
```bash
# Voir les logs du pod
kubectl -n shopflow-staging describe pod <POD_NAME>
kubectl -n shopflow-staging logs <POD_NAME> --previous  # si crashed

# Vérifier si l'image est pullable
kubectl -n shopflow-staging get pods -o jsonpath='{.items[*].status.containerStatuses[*].state}'

# Vérifier les événements du namespace
kubectl -n shopflow-staging get events --sort-by='.lastTimestamp'
```

### 2.4 Structure complète post-déploiement

Après un déploiement réussi, vous devez voir :

```bash
# Vérifier tous les éléments Helm déployés
kubectl -n shopflow-staging get all -l app.kubernetes.io/instance=shopflow-staging

# Retour attendu :
# DEPLOYMENT, POD, REPLICASET, SERVICE, HPA, INGRESS, 
# CONFIGMAP, SECRET (tous créés par Helm)

# Vérifier les labels (permet à ArgoCD de tracker les ressources)
kubectl -n shopflow-staging get deploy shopflow-staging-shopflow \
  -o jsonpath='{.metadata.labels}' | jq .

# Voir les relationships (qui a créé quoi)
kubectl -n shopflow-staging get deploy shopflow-staging-shopflow \
  -o jsonpath='{.metadata.ownerReferences}' | jq .
```

---

## 🔀 Étape 3 : Promotion vers Production

### 3.0 Stratégie de promotion

**ShopFlow utilise une promotion gérée et contrôlée :**
- **Staging** : Auto-sync depuis CI (immédiat, à chaque commit)
- **Production** : Sync manuel (requires approval, promotion explicite)

**Avantages:**
- **Safety** : Validation en staging avant prod
- **Auditability** : Chaque promotion est une PR reviewable et traceable
- **Rollback** : Facile de revenir à une version précédente (revert la PR)

### 3.1 Vérifier que staging est stable

**Avant de promouvoir, validez en staging :**

```bash
# 1. Vérifier le statut du déploiement staging
kubectl -n shopflow-staging get deploy,pods

# 2. Vérifier les métriques (CPU, Memory)
kubectl -n shopflow-staging top pods
kubectl -n shopflow-staging top nodes

# 3. Vérifier les logs pour des erreurs
kubectl -n shopflow-staging logs -f deploy/shopflow-staging-shopflow --tail=50

# 4. Tester l'accès à l'application (healthcheck)
kubectl -n shopflow-staging exec -it <POD_NAME> -- /bin/sh -c "curl http://localhost:8000/healthz"

# 5. Vérifier l'Ingress
kubectl -n shopflow-staging get ingress
curl -I $(kubectl -n shopflow-staging get ingress -o jsonpath='{.items[0].spec.rules[0].host}')

# 6. Vérifier le statut ArgoCD (pas de drift)
kubectl -n argocd get application shopflow-staging -o jsonpath='{.status.sync.status}'
# Résultat attendu: "Synced"
```

### 3.2 Extraire le tag de staging

```bash
# Récupérer le tag actuellement déployé en staging
STAGING_TAG=$(kubectl -n shopflow-staging get deploy shopflow-staging-shopflow \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $NF}')

echo "Staging tag to promote: $STAGING_TAG"

# Ou depuis le repo
cd shopflow-gitops
STAGING_TAG=$(grep "tag:" envs/staging/values-staging.yaml | grep -v '#' | head -1 | awk '{print $2}' | tr -d '"')
echo "Tag from values: $STAGING_TAG"
```

### 3.3 Créer une PR de promotion (Git workflow)

**Processus recommandé (avec review):**

```bash
# 1. Clone/Fetch le repo GitOps
cd shopflow-gitops
git fetch origin
git pull origin main

# 2. Créer une branche de promotion
git checkout -b promote/$STAGING_TAG

# 3. Mettre à jour les values de production
# Remplacer le tag image en prod
sed -i "s|tag:.*|tag: $STAGING_TAG|" envs/prod/values-prod.yaml

# Vérifier le changement
grep "tag:" envs/prod/values-prod.yaml

# 4. Committer
git add envs/prod/values-prod.yaml
git commit -m "chore(prod): promote image $STAGING_TAG from staging"

# 5. Pousser et créer PR
git push origin promote/$STAGING_TAG

# (Accéder à GitHub pour créer la PR et merge)
```

**Ou directement depuis la CLI (pour environnements non-prod uniquement):**

```bash
# 1. Mettre à jour en local
STAGING_TAG=$(grep "tag:" envs/staging/values-staging.yaml | head -1 | awk '{print $2}' | tr -d '"')
sed -i "s|tag:.*|tag: $STAGING_TAG|g" envs/prod/values-prod.yaml

# 2. Vérifier avant de committer
git diff envs/prod/values-prod.yaml

# 3. Committer et pousser
git add envs/prod/values-prod.yaml
git commit -m "chore(prod): promote $STAGING_TAG"
git push origin main
```

### 3.4 Vérifier la promotion en production

**Une fois la PR mergée, ArgoCD synchronise automatiquement:**

```bash
# 1. Attendre 3-5 minutes le sync d'ArgoCD (poll interval)
# Ou forcer une sync immédiate :
kubectl -n argocd patch application shopflow-prod \
  -p '{"spec":{"syncPolicy":{"syncOptions":["Prune=true"]}}}' --type merge

# 2. Vérifier le statut de sync
kubectl -n argocd get application shopflow-prod -o jsonpath='{.status.sync.status}'

# 3. Voir l'image maintenant déployée en prod
kubectl -n shopflow-prod get deploy shopflow-prod-shopflow \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# 4. Vérifier les pods en prod
kubectl -n shopflow-prod get pods -o wide
kubectl -n shopflow-prod get deploy -o wide

# 5. Vérifier les métriques
kubectl -n shopflow-prod top pods

# 6. Vérifier les logs pour des erreurs
kubectl -n shopflow-prod logs -f deploy/shopflow-prod-shopflow --tail=100

# 7. Tester l'accès (si Ingress configuré)
PROD_INGRESS=$(kubectl -n shopflow-prod get ingress -o jsonpath='{.items[0].spec.rules[0].host}')
curl -I http://$PROD_INGRESS

# 8. Vérifier la différence Git vs Cluster
kubectl -n argocd describe application shopflow-prod | grep "OutOfSync" -A 5
```

### 3.5 Rollback en cas de problème

**Si la production pose problème, reverter la promotion :**

```bash
# 1. Identifier le commit précédent
cd shopflow-gitops
git log --oneline envs/prod/values-prod.yaml | head -5

# 2. Revert le commit de promotion
git revert <COMMIT_SHA>
git push origin main

# 3. ArgoCD reconcilie automatiquement vers la version précédente
kubectl -n shopflow-prod get pods  # Voir les changements

# 4. Vérifier que l'ancienne image tourne
kubectl -n shopflow-prod get deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## 🔍 Étape 4 : Commandes opérationnelles essentielles

### 4.0 Classification des commandes

Les commandes opérationnelles sont organisées par objectif :
- **Verification** : Valider l'état du cluster et des déploiements
- **Monitoring** : Examiner les métriques et les performances
- **Debugging** : Diagnostiquer et résoudre les problèmes
- **Management** : Contrôler et mettre à jour les déploiements

### 4.1 Vérification globale du cluster

**Objectif:** État général du cluster et de tous les composants

```bash
# === Vue globale ===
echo "=== Cluster Info ===" && kubectl cluster-info
echo -e "\n=== Nodes Status ===" && kubectl get nodes -o wide
echo -e "\n=== All Namespaces ===" && kubectl get ns

# === Namespace par namespace ===
for ns in shopflow-staging shopflow-prod monitoring argocd ingress-nginx; do
  echo -e "\n=== $ns ===" && kubectl get all -n $ns
done

# === ArgoCD Applications ===
echo -e "\n=== ArgoCD Applications ===" && kubectl get applications -n argocd
echo -e "\n=== ArgoCD Sync Status ===" && \
  kubectl get applications -n argocd -o wide -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

# === Ressources critiques (tous les namespaces) ===
echo -e "\n=== Ingress Controllers ===" && kubectl get ingress -A
echo -e "\n=== Services (LoadBalancer) ===" && kubectl get svc -A | grep LoadBalancer
echo -e "\n=== Services (NodePort) ===" && kubectl get svc -A | grep NodePort
```

### 4.2 Monitoring ArgoCD

**Objectif:** Vérifier que les Applications ArgoCD sont en sync et healthy

**Comprendre les états ArgoCD:**
- **Sync Status** : Git vs Cluster (Synced = identique)
- **Health Status** : Application fonctionne correctement (Healthy = ok)
- **OutOfSync** : Le cluster a divergé de Git (manual change détecté)

```bash
# === Vue compacte ===
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REPO:.spec.source.repoURL

# === Détail complet d'une application ===
kubectl -n argocd describe application shopflow-staging

# === État de sync détaillé ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status}' | jq '.sync, .health'

# === Voir ce qui est managé par ArgoCD ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.resources}' | jq '.[] | {kind, name, namespace, health}'

# === Vérifier les différences Git vs Cluster (drift) ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.operationState}' | jq '.'

# === Voir les événements ArgoCD ===
kubectl -n argocd get events --field-selector involvedObject.name=shopflow-staging

# === Forcer un refresh et sync ===
# Refresh : relit depuis Git (peut prendre quelques secondes)
kubectl -n argocd patch application shopflow-staging \
  -p '{"status":{"operationState":{"phase":"Running"}}}' --type merge

# Sync : applique au cluster
kubectl -n argocd patch application shopflow-staging \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'
```

### 4.3 Vérification des déploiements applicatifs

**Objectif:** S'assurer que les applications tournent correctement

```bash
# === État général du namespace ===
kubectl get all -n shopflow-staging --show-kind

# === Deployments (desired vs ready replicas) ===
kubectl get deploy -n shopflow-staging -o wide
kubectl get deploy -n shopflow-staging -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,UP-TO-DATE:.status.updatedReplicas,AVAILABLE:.status.availableReplicas

# === Pods individuels ===
kubectl get pods -n shopflow-staging -o wide
kubectl get pods -n shopflow-staging -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status,RESTARTS:.status.containerStatuses[0].restartCount

# === ReplicaSet (pour voir si c'est un problème de nouvelle version) ===
kubectl get replicaset -n shopflow-staging -o wide

# === Voir l'image d'un pod ===
kubectl get pods -n shopflow-staging -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# === Voir les labels (utilisés pour selector les pods) ===
kubectl get pods -n shopflow-staging -o wide -L app,version,release

# === PVC et storage ===
kubectl get pvc -n shopflow-staging
kubectl get pv
```

### 4.4 Monitoring des ressources et performance

**Objectif:** Vérifier CPU, Memory et autoscaling

```bash
# === Node resources (capacité du cluster) ===
kubectl top nodes
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory

# === Pod resources (actualuel usage) ===
kubectl top pods -n shopflow-staging
kubectl top pods -n shopflow-prod

# === HPA (Horizontal Pod Autoscaling) status ===
kubectl get hpa -n shopflow-staging -o wide
kubectl describe hpa -n shopflow-staging shopflow-staging-shopflow

# === Détail HPA avec metrics ===
kubectl get hpa -n shopflow-staging -o custom-columns=NAME:.metadata.name,REFERENCE:.spec.scaleTargetRef.name,TARGETS:.status.currentMetrics[*].resource.current.averageUtilization,MINPODS:.spec.minReplicas,MAXPODS:.spec.maxReplicas,REPLICAS:.status.currentReplicas

# === Resource Requests vs Limits ===
kubectl get pods -n shopflow-staging -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources}{"\n"}{end}' | jq .

# === Quotas du namespace ===
kubectl get resourcequota -n shopflow-staging -o wide
kubectl describe resourcequota -n shopflow-staging
```

### 4.5 Logs et debugging

**Objectif:** Analyser les erreurs et comportement des applications

```bash
# === Logs applicatifs en temps réel ===
kubectl logs -f deploy/shopflow-staging-shopflow -n shopflow-staging --all-containers=true
kubectl logs -f -l app.kubernetes.io/name=shopflow -n shopflow-staging --tail=100

# === Logs historiques (pod peut avoir crashé) ===
kubectl logs -n shopflow-staging <POD_NAME> --previous
kubectl logs -n shopflow-staging <POD_NAME> --all-containers=true

# === Voir les derniers logs de tous les pods ===
kubectl logs -n shopflow-staging -f -l app=shopflow-staging --all-pods=true --max-log-requests=10

# === Logs containers initiation (si problème de démarrage) ===
kubectl describe pod <POD_NAME> -n shopflow-staging | grep -A 20 "Events:"

# === Voir en détail un pod qui crashe ===
kubectl describe pod <POD_NAME> -n shopflow-staging
kubectl get pod <POD_NAME> -n shopflow-staging -o yaml

# === Shell dans un pod pour tester ===
kubectl exec -it <POD_NAME> -n shopflow-staging -- /bin/sh
# Dans le pod : curl http://localhost:8000/healthz, ps aux, etc.

# === Port-forward pour tester localement ===
kubectl port-forward -n shopflow-staging pod/<POD_NAME> 8080:8000 &
# Puis: curl http://localhost:8080

# === Voir tous les événements d'un namespace ===
kubectl get events -n shopflow-staging --sort-by='.lastTimestamp'
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### 4.6 Configuration (ConfigMaps, Secrets)

**Objectif:** Vérifier que les configurations et secrets sont correctement injectés

```bash
# === ConfigMaps (configuration non-sensible) ===
kubectl get configmap -n shopflow-staging
kubectl get configmap -n shopflow-staging shopflow-staging-shopflow -o yaml

# === Récupérer des valeurs de ConfigMap ===
kubectl get configmap shopflow-staging-shopflow -n shopflow-staging \
  -o jsonpath='{.data.LOG_LEVEL}'

# === Secrets (données sensibles, encodées en base64) ===
kubectl get secret -n shopflow-staging
kubectl describe secret shopflow-staging-shopflow-secret -n shopflow-staging

# === Voir les données d'un secret (décodé) ===
kubectl get secret shopflow-staging-shopflow-secret -n shopflow-staging \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d

# === Vérifier qu'un secret est monté en volume ===
kubectl get pod <POD_NAME> -n shopflow-staging -o jsonpath='{.spec.volumes[?(@.secret)]}' | jq .

# === Vérifier les variables d'environnement du pod ===
kubectl set env pods/<POD_NAME> --list -n shopflow-staging
```

### 4.7 Services et Networking

**Objectif:** Vérifier la connectivité réseau et l'exposition des services

```bash
# === Services (accès réseau interne) ===
kubectl get svc -n shopflow-staging -o wide
kubectl get endpoints -n shopflow-staging

# === Détail d'un service ===
kubectl describe svc shopflow-staging-shopflow -n shopflow-staging

# === Tester la DNS du service (depuis un pod) ===
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -n shopflow-staging -- \
  nslookup shopflow-staging-shopflow.shopflow-staging.svc.cluster.local

# === Tester la connectivité vers un service ===
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -n shopflow-staging -- \
  curl http://shopflow-staging-shopflow:80/healthz

# === Ingress (accès HTTP/HTTPS externe) ===
kubectl get ingress -n shopflow-staging -o wide
kubectl describe ingress -n shopflow-staging

# === Vérifier la resolution DNS du Ingress ===
curl -I http://shopflow-staging.example.com

# === Voir quelle IP publique le Ingress a obtenu ===
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# === Network Policies (contrôle de flux réseau) ===
kubectl get networkpolicy -n shopflow-staging
kubectl describe networkpolicy -n shopflow-staging
```

### 4.7.1 Test en Cloud Shell: comparer staging et prod

**Objectif:** Vérifier localement les deux environnements sans modifier le cluster.

Avec la configuration actuelle, l'Ingress utilise un hostname différent pour chaque environnement et un chemin dédié :
- staging : `shopflow-staging.example.com` + `/staging`
- prod : `shopflow.example.com` + `/prod`

```bash
# Récupérer l'IP publique de l'Ingress controller
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$INGRESS_IP"

# Tester staging via Host header et path dédié
curl -i -H "Host: shopflow-staging.example.com" http://$INGRESS_IP/staging/
curl -i -H "Host: shopflow-staging.example.com" http://$INGRESS_IP/staging/healthz

# Tester prod via Host header et path dédié
curl -i -H "Host: shopflow.example.com" http://$INGRESS_IP/prod/
curl -i -H "Host: shopflow.example.com" http://$INGRESS_IP/prod/healthz
```

### 4.7.2 Test en local avec port-forward

**Objectif:** Comparer staging et prod depuis Cloud Shell ou un terminal local sans dépendre de l'IP externe.

```bash
# Ouvrir deux tunnels dans deux terminaux séparés
kubectl -n shopflow-staging port-forward svc/shopflow-staging-shopflow 8081:80
kubectl -n shopflow-prod port-forward svc/shopflow-prod-shopflow 8082:80

# Tester les deux environnements en local
curl -i http://localhost:8081/
curl -i http://localhost:8081/healthz

curl -i http://localhost:8082/
curl -i http://localhost:8082/healthz
```

**Lecture des différences attendues:**
- `shopflow-staging` doit refléter les paramètres staging : `replicaCount: 2`, `LOG_LEVEL: info`
- `shopflow-prod` doit refléter les paramètres prod : `replicaCount: 4`, `LOG_LEVEL: warning`
- Si l'application affiche l'environnement, la réponse HTTP ou les logs doivent différer entre staging et prod

### 4.8 Helm operations

**Objectif:** Inspecter et gérer les Helm releases

**Comprendre Helm vs ArgoCD:**
- **Helm** : Template engine + package manager
- **ArgoCD** : Orchestre les Helm releases, gère le versioning Git

```bash
# === Lister les releases Helm ===
helm list -n shopflow-staging
helm list -A

# === Voir les valeurs appliquées à une release ===
helm get values shopflow-staging -n shopflow-staging
helm get values shopflow-staging -n shopflow-staging -o yaml | less

# === Voir le manifest généré (Helm + values appliquées) ===
helm get manifest shopflow-staging -n shopflow-staging | less

# === Vérifier la définition du chart ===
helm show chart shopflow --repo https://github.com/oderbel-DS/shopflow-gitops/charts/shopflow

# === Template local avant d'appliquer ===
helm template shopflow shopflow --values envs/staging/values-staging.yaml \
  -f charts/shopflow/values.yaml

# === Voir l'historique des releases ===
helm history shopflow-staging -n shopflow-staging

# === Notes de release (informations du chart) ===
helm get notes shopflow-staging -n shopflow-staging

# === Vérifier les dépendances du chart ===
cd shopflow-gitops
helm dependency list charts/shopflow/
```

### 4.9 ArgoCD Application inspection en détail

**Objectif:** Analyse complète du statut ArgoCD

```bash
# === État de synchronisation complet ===
kubectl -n argocd get application shopflow-staging -o yaml | grep -A 20 "status:"

# === Ressources individuelles et leur santé ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.resources[*]}' | jq '.[] | {kind, name, namespace, health, syncWave}'

# === Voir le commit Git actuel ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.sync.revision}'

# === Voir l'operation récente (sync/refresh) ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.operationState}' | jq '.'

# === Voir les conditions d'erreur ===
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.conditions}' | jq '.[] | {type, message}'

# === Comparer l'état souhaité vs actuel (dans ArgoCD logs) ===
kubectl -n argocd logs -f -l app.kubernetes.io/name=argocd-application-controller | grep shopflow-staging
```

---

## 🔐 Étape 5 : Sécurité et gestion des secrets

### 5.0 Modèle de sécurité

ShopFlow utilise une approche en couches pour protéger les données sensibles :

1. **Secrets GitHub** : Credentiels pour build et push (stockage GitHub chiffré)
2. **Service Account GCP** : Accès à Artifact Registry (clé JSON)
3. **Secrets Kubernetes** : Credentials injectées dans les pods
4. **Network Policies** : Isolation du trafic réseau entre namespaces

### 5.1 Secrets GitHub (CI/CD credentials)

**Objectif:** Configurer les credentiels pour que la CI accède à GCP et à GitOps repo

**À configurer une seule fois sur:** https://github.com/oderbel-DS/shopflow/settings/secrets/actions

```bash
# === GCP_PROJECT ===
# Valeur : shopflow-499020
# Rôle : Identifie le projet GCP pour Artifact Registry

# === GCP_SA_KEY ===
# Valeur : Contenu complet du fichier JSON (clé de service account)
# Rôle : Authentifie la CI pour pusher les images
# Comment l'obtenir :
gcloud iam service-accounts keys create ~/gcp-key.json \
  --iam-account=github-actions@shopflow-499020.iam.gserviceaccount.com

# Puis copier le contenu du fichier JSON dans le secret GitHub

# === GITOPS_PAT ===
# Valeur : Personal Access Token GitHub
# Rôle : Authentifie la CI pour pusher dans shopflow-gitops
# Scopes : repo (full control of repos), workflow (pour les actions)
# Comment l'obtenir :
# Aller à https://github.com/settings/tokens/new
# Sélectionner : repo, workflow
# Copier le token dans le secret GitHub
```

**Vérification:**
```bash
# Voir les secrets configurés (ne montre pas les valeurs)
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/oderbel-DS/shopflow/actions/secrets

# Tester que la CI peut s'authentifier (vérifier les runs)
# Accéder à : https://github.com/oderbel-DS/shopflow/actions
```

### 5.2 Secrets Kubernetes

**Objectif:** Gérer les secrets applicatifs (DB_PASSWORD, API keys, etc.)

**Couche 1 : Déclaration (Chart Helm)**

Le chart définit un template Secret :

```yaml
# charts/shopflow/templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "shopflow.fullname" . }}-secret
type: Opaque
data:
  DB_PASSWORD: {{ .Values.secrets.DB_PASSWORD | b64enc | quote }}
  API_KEY: {{ .Values.secrets.API_KEY | b64enc | quote }}
```

**Couche 2 : Population des values**

Les valeurs réelles viennent de `envs/staging/values-staging.yaml` :

```yaml
secrets:
  DB_PASSWORD: "encrypted-password-here"
  API_KEY: "api-key-here"
```

**Couche 3 : Injection dans le pod**

Le Deployment monte le Secret en tant que variables d'environnement :

```yaml
# charts/shopflow/templates/deployment.yaml
containers:
- name: backend
  envFrom:
  - secretRef:
      name: shopflow-staging-shopflow-secret
```

**Commandes pour gérer les secrets :**

```bash
# === Lister les secrets d'un namespace ===
kubectl get secret -n shopflow-staging
kubectl get secret -n shopflow-staging -o wide

# === Voir les données d'un secret (encodées en base64) ===
kubectl get secret shopflow-staging-shopflow-secret -n shopflow-staging \
  -o yaml | grep "^  [A-Z]" | head -5

# === Décoder un secret spécifique ===
kubectl get secret shopflow-staging-shopflow-secret -n shopflow-staging \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d ; echo

# === Créer un secret manuellement (si besoin) ===
kubectl create secret generic shopflow-secret \
  --from-literal=DB_PASSWORD=my-secret-password \
  --from-literal=API_KEY=my-api-key \
  -n shopflow-staging

# === Mettre à jour un secret (faire un patch) ===
kubectl patch secret shopflow-staging-shopflow-secret \
  -n shopflow-staging -p "{\"data\":{\"DB_PASSWORD\":\"$(echo -n 'new-password' | base64 -w0)\"}}"

# === Supprimer un secret ===
kubectl delete secret shopflow-staging-shopflow-secret -n shopflow-staging

# === Vérifier qu'un secret est bien monté dans le pod ===
kubectl exec -it <POD_NAME> -n shopflow-staging -- env | grep DB_PASSWORD
```

### 5.3 Best practices pour les secrets

**⚠️ À FAIRE:**
- ✅ Stocker les secrets dans des variables d'environnement Kubernetes (pas en clair dans le code)
- ✅ Utiliser des Service Accounts avec RBAC limité (least privilege)
- ✅ Rotationner les secrets régulièrement
- ✅ Auditer l'accès aux secrets (Kubernetes API server logs)
- ✅ Chiffrer les secrets en repos (etcd encryption)

**❌ À ÉVITER:**
- ❌ Committer les secrets dans Git (même chiffrés sans les clés disponibles)
- ❌ Utiliser des credentiels root ou admin dans les pods
- ❌ Exposer les secrets en logs ou events
- ❌ Utiliser des secrets hardcodés dans les Dockerfiles

### 5.4 Network Policies

**Objectif:** Contrôler le trafic réseau entre pods et namespaces

Les Network Policies déclarées dans `bootstrap/network-policies/` isolent :
- Staging ↔ Prod (pas d'accès direct)
- Chaque namespace ↔ Monitoring (pour Prometheus scrape)

```bash
# === Voir les Network Policies ===
kubectl get networkpolicy -A
kubectl describe networkpolicy -n shopflow-staging

# === Tester la connectivité (elle doit échouer si isolée) ===
# Depuis staging vers prod (doit échouer)
kubectl run -it --rm debug --image=nicolaka/netshoot -n shopflow-staging -- \
  curl -I http://shopflow-prod-shopflow.shopflow-prod.svc.cluster.local:80

# Depuis prod vers staging (doit échouer)
kubectl run -it --rm debug --image=nicolaka/netshoot -n shopflow-prod -- \
  curl -I http://shopflow-staging-shopflow.shopflow-staging.svc.cluster.local:80

# Vers monitoring (doit réussir pour Prometheus)
kubectl run -it --rm debug --image=nicolaka/netshoot -n shopflow-staging -- \
  curl -I http://kps-prometheus.monitoring.svc.cluster.local:9090
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

## 🛠️ Étape 6 : Troubleshooting et diagnostique

### 6.0 Méthodologie de troubleshooting

**Approche systématique** (du bas vers le haut) :

1. **Cluster** : Vérifier que le cluster GKE fonctionne
2. **Namespaces** : Vérifier l'existence et l'isolation
3. **Plateforme** : Vérifier ArgoCD, Ingress, Monitoring
4. **ArgoCD** : Vérifier la synchronisation Git
5. **Helm** : Vérifier le rendu des templates
6. **Kubernetes** : Vérifier les Deployments, Pods, Services
7. **Application** : Vérifier les logs et les probes

### 6.1 Les pods ne démarrent pas (ImagePullBackOff, CrashLoopBackOff)

**Symptômes:** Pod en état `Pending`, `ImagePullBackOff`, ou `CrashLoopBackOff`

```bash
# === Diagnostic ===
kubectl -n shopflow-staging describe pod <POD_NAME>
# Chercher la section "Events:" pour voir l'erreur

# === Cause 1 : Image inexistante ou inaccessible ===

# Vérifier que l'image existe dans Artifact Registry
gcloud artifacts docker tags list \
  northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend \
  --filter=tag:sha-120278a

# Vérifier que le pod peut accéder à l'Artifact Registry
# (regarder si une ImagePullSecret est configurée)
kubectl get pod <POD_NAME> -n shopflow-staging -o jsonpath='{.spec.imagePullSecrets}'

# === Cause 2 : Image pull secret manquant ===

# Créer le secret d'authentification Artifact Registry
kubectl create secret docker-registry gcr-json-key \
  --docker-server=northamerica-northeast2-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat ~/gcp-key.json)" \
  -n shopflow-staging

# Ajouter le secret au service account
kubectl patch serviceaccount default -n shopflow-staging \
  -p '{"imagePullSecrets": [{"name": "gcr-json-key"}]}'

# === Cause 3 : Application crashe au démarrage ===

# Voir les logs du container
kubectl logs -n shopflow-staging <POD_NAME> --previous

# Vérifier les variables d'environnement
kubectl exec -it <POD_NAME> -n shopflow-staging -- env | sort

# Vérifier les fichiers config
kubectl exec -it <POD_NAME> -n shopflow-staging -- ls -la /etc/config/

# === Cause 4 : Insuffisance de ressources ===

# Vérifier les demandes (requests)
kubectl get pod <POD_NAME> -n shopflow-staging \
  -o jsonpath='{.spec.containers[*].resources}'

# Vérifier l'espace disponible sur les nœuds
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Augmenter les limites si nécessaire (mettre à jour values.yaml)
```

### 6.2 ArgoCD n'applique pas les changements (OutOfSync)

**Symptômes:** `kubectl get application shopflow-staging` montre `OutOfSync`

```bash
# === Diagnostic ===

# Vérifier le statut de sync
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.sync.status}'

# Voir ce qui diffère
kubectl -n argocd describe application shopflow-staging | tail -20

# Voir les ressources non-synchronized
kubectl -n argocd get application shopflow-staging \
  -o jsonpath='{.status.resources[*]}' | jq '.[] | select(.syncWave != 0)'

# === Solution 1 : Refresh de la détection ===

# Forcer ArgoCD à relire depuis Git
kubectl -n argocd patch application shopflow-staging \
  -p '{"status":{"operationState":{"finishedAt":null}}}' --type merge

# Forcer un sync complet
kubectl -n argocd patch application shopflow-staging \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# === Solution 2 : Vérifier le Git ===

# Vérifier que la branche existe
git -C shopflow-gitops log --oneline | head -5

# Vérifier que les fichiers YAML sont valides
kubectl apply -f envs/staging/values-staging.yaml --dry-run=client

# === Solution 3 : Vérifier l'accès au repo ===

# Vérifier que ArgoCD peut cloner le repo
kubectl -n argocd logs deploy/argocd-repo-server | grep shopflow-gitops

# Si repo privée, vérifier que les credentials SSH/HTTPS sont configurés
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository

# === Solution 4 : Effacer et redéployer ===

# Supprimer l'application (elle va être recréée par le root-app)
kubectl delete application shopflow-staging -n argocd

# AttendreArgoCD recréer et resyncer (peut prendre 5 minutes)
```

### 6.3 Service n'est pas accessible (pas de LoadBalancer IP)

**Symptômes:** Ingress ou LoadBalancer service pas d'IP externe

```bash
# === Diagnostic ===

# Vérifier le service
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Column EXTERNAL-IP doit avoir une IP (pas <pending>)

# === Solution 1 : Attendre que l'IP soit assignée ===

# GCP peut prendre 2-5 minutes pour assigner une IP
kubectl get svc -n ingress-nginx ingress-nginx-controller --watch

# === Solution 2 : Vérifier qu'il y a des nœuds disponibles ===

kubectl get nodes
# Tous les nœuds doivent être Ready

# === Solution 3 : Vérifier les quota GCP ===

gcloud compute project-info describe --project=shopflow-499020 | grep -i quota

# === Solution 4 : Utiliser NodePort au lieu de LoadBalancer ===

# Passer le service de LoadBalancer à NodePort
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"type":"NodePort"}}'

# Récupérer le port assigné
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[0].nodePort}'
```

### 6.4 Image ne change pas après CI

**Symptômes:** Nouveau commit pushé, mais pod utilise toujours l'ancienne image

```bash
# === Diagnostic ===

# Vérifier que le workflow GitHub a réussi
# Accéder à : https://github.com/oderbel-DS/shopflow/actions

# Vérifier que le nouveau tag existe dans Artifact Registry
gcloud artifacts docker tags list \
  northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend \
  --sort-by=~UPDATE_TIME --limit=3

# Vérifier que le tag a été mis à jour dans Git
git -C shopflow-gitops log --oneline envs/staging/values-staging.yaml | head -3
git -C shopflow-gitops diff HEAD~1 envs/staging/values-staging.yaml | grep -i tag

# === Solution 1 : Forcer ArgoCD à rafraîchir ===

# Forcer un refresh
kubectl -n argocd patch application shopflow-staging \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Attendre la sync (peut prendre 3-5 minutes)
kubectl -n argocd get application shopflow-staging --watch

# === Solution 2 : Vérifier que le nouveau Pod a démarré ===

# Voir les pods (les anciens devraient être en Terminating)
kubectl get pods -n shopflow-staging -o wide -w

# Si les pods ne changent pas, forcer une rollout restart
kubectl rollout restart deployment/shopflow-staging-shopflow -n shopflow-staging

# === Solution 3 : Vérifier qu'ArgoCD peut écrire dans Git ===

# L'application GitHub Actions doit avoir l'accès nécessaire
# Vérifier les secrets GitHub (voir section 5.1)

# Voir les logs du job d'update GitOps
# Accéder à : https://github.com/oderbel-DS/shopflow/actions/workflows/ci-backend.yaml
# Voir la dernière run, section "Update GitOps repository"
```

### 6.5 HPA (Autoscaling) ne fonctionne pas

**Symptômes:** HPA créé mais toujours avec le nombre initial de replicas

```bash
# === Diagnostic ===

# Vérifier l'état HPA
kubectl get hpa -n shopflow-staging shopflow-staging-shopflow
kubectl describe hpa -n shopflow-staging shopflow-staging-shopflow

# Vérifier les métriques
kubectl top pods -n shopflow-staging

# === Cause 1 : Metrics Server pas installé ===

# Vérifier que metrics-server est présent
kubectl get deployment metrics-server -n kube-system

# Si absent, installer :
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# === Cause 2 : Pod n'a pas de resource requests ===

# HPA calcule les pourcentages basé sur les requests
# Vérifier que les requests sont définies
kubectl get pod <POD_NAME> -n shopflow-staging \
  -o jsonpath='{.spec.containers[*].resources.requests}'

# Doit montrer : cpu et memory

# === Cause 3 : Pas assez de charge ===

# Générer une charge de test
kubectl run -i --tty load-generator \
  --rm --image=busybox:1.28 --restart=Never \
  -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://shopflow-staging-shopflow.shopflow-staging:80/; done"

# Vérifier que HPA scale up
kubectl get hpa -n shopflow-staging -w
```

### 6.6 Ingress ne routage pas (404, Connection refused)

**Symptômes:** Erreur 404 ou Connection refused accédant via Ingress hostname

```bash
# === Diagnostic ===

# Vérifier la configuration Ingress
kubectl get ingress -n shopflow-staging
kubectl describe ingress -n shopflow-staging

# Vérifier que le backend service existe
kubectl get svc -n shopflow-staging shopflow-staging-shopflow

# === Solution 1 : Vérifier la resolution DNS ===

# Tester que le hostname se résout
nslookup shopflow-staging.example.com
# Doit retourner l'IP du Ingress controller

# Récupérer cette IP
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# === Solution 2 : Tester l'accès direct au pod ===

# Créer un tunnel vers le pod
kubectl port-forward -n shopflow-staging pod/<POD_NAME> 8080:8000 &

# Tester localement
curl http://localhost:8080/healthz

# === Solution 3 : Vérifier que le Ingress pointe vers le bon backend ===

# Voir la configuration Ingress YAML
kubectl get ingress -n shopflow-staging -o yaml

# Vérifier que le service name et port correspondent
# service:
#   name: shopflow-staging-shopflow  ← Doit exister
#   port:
#     number: 80                      ← Service port

# === Solution 4 : Vérifier les logs du Ingress Controller ===

kubectl logs -n ingress-nginx -f -l app.kubernetes.io/component=controller | grep shopflow
```

### 6.7 Quota atteint (resourcequotas exceeded)

**Symptômes:** Pod ne peut pas être créé, erreur "exceeded quota"

```bash
# === Diagnostic ===

# Voir l'utilisation des quotas
kubectl describe resourcequota -n shopflow-staging

# Voir les objets qui consomment des quotas
kubectl get pods,deploy,svc -n shopflow-staging --show-kind

# === Solution 1 : Augmenter le quota ===

# Modifier envs/staging/quota-staging.yaml
# Augmenter les limites de requests/limits

kubectl apply -f bootstrap/quotas/quota-staging.yaml

# === Solution 2 : Réduire les resource requests ===

# Modifier charts/shopflow/values.yaml
# Réduire les requests/limits des pods

helm upgrade shopflow-staging shopflow \
  -f charts/shopflow/values.yaml \
  -f envs/staging/values-staging.yaml \
  -n shopflow-staging
```

### 6.8 Commandes universelles de diagnostic

```bash
# === Voir TOUS les problèmes du cluster ===
kubectl get events -A --sort-by='.lastTimestamp'

# === Vérifier les conditions des nœuds ===
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,AGE:.metadata.creationTimestamp,KUBELET_VERSION:.status.nodeInfo.kubeletVersion

# === Vérifier la version de l'API ===
kubectl version

# === Exporter la config complète d'une application pour debugger ===
kubectl -n shopflow-staging get all -o yaml > /tmp/staging-export.yaml

# === Comparer deux versions d'une ressource ===
kubectl get deploy shopflow-staging-shopflow -n shopflow-staging -o yaml > /tmp/current.yaml
helm template shopflow shopflow -f envs/staging/values-staging.yaml > /tmp/expected.yaml
diff /tmp/current.yaml /tmp/expected.yaml
```

---

## 📚 Étape 7 : Référence des fichiers et architecture

### 7.1 Valeurs clés de la configuration

| Paramètre | Valeur | Rôle |
|-----------|--------|------|
| **Projet GCP** | `shopflow-499020` | Conteneur des ressources GCP |
| **Région** | `northamerica-northeast2` | Localisation cluster + Artifact Registry |
| **Cluster GKE** | `shopflow-cluster` | Nom du cluster Kubernetes |
| **Container Registry** | `northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow` | Repo centralisée des images |
| **Image backend** | `northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend` | Image Docker backend |
| **Tag courant (staging)** | `sha-120278a` | Commit SHA utilisé |
| **Repo applicatif** | `github.com/oderbel-DS/shopflow` | Code source + CI |
| **Repo GitOps** | `github.com/oderbel-DS/shopflow-gitops` | Configuration + ArgoCD |
| **Release staging** | `shopflow-staging` | Helm release name |
| **Release prod** | `shopflow-prod` | Helm release name |
| **Namespace staging** | `shopflow-staging` | Isolation staging |
| **Namespace prod** | `shopflow-prod` | Isolation production |

### 7.2 Fichiers clés à connaître

#### **Dans `shopflow` (dépôt applicatif)**

| Fichier | Rôle | Type |
|---------|------|------|
| `.github/workflows/ci-backend.yaml` | Pipeline CI : build → scan → push → gitops update | GitHub Actions |
| `bootstrap/namespaces.yaml` | Déclaration des namespaces Kubernetes | Manifest K8s |
| `bootstrap/platform/values-*.yaml` | Configuration Helm pour Ingress, Monitoring, ArgoCD | Values Helm |
| `bootstrap/quotas/quota-*.yaml` | Resource quotas par environment | Manifest K8s |
| `bootstrap/network-policies/` | Isolation réseau entre namespaces | Manifest K8s |
| `backend/Dockerfile` | Définition image Docker backend | Dockerfile |
| `frontend/Dockerfile` | Définition image Docker frontend | Dockerfile |
| `README.md` | Documentation applicative | Doc |

#### **Dans `shopflow-gitops` (dépôt GitOps - source unique de vérité)**

| Fichier | Rôle | Frequency update |
|---------|------|------------------|
| `apps/argocd-root-app.yaml` | Entry point App-of-Apps (orchestre tout) | Au bootstrap |
| `apps/argocd-shopflow-staging.yaml` | ArgoCD Application pour staging | Au bootstrap |
| `apps/argocd-shopflow-prod.yaml` | ArgoCD Application pour prod | Au bootstrap |
| `charts/shopflow/Chart.yaml` | Metadata du chart Helm | Rarement |
| `charts/shopflow/values.yaml` | Valeurs par défaut Helm (tous envs) | À chaque release |
| `charts/shopflow/templates/*.yaml` | Templates Kubernetes Helm | À chaque release |
| `envs/staging/values-staging.yaml` | Surcharges staging (surtout image.tag) | À chaque CI |
| `envs/prod/values-prod.yaml` | Surcharges prod (surtout image.tag) | À chaque promotion |
| `README.md` | Architecture et flux déploiement | Documentation |

### 7.3 Flux de mise à jour

```
1. MODIFICATION CODE
   └─→ shopflow/backend/app/main.py
       │
       └─→ git commit + git push
           │
           └─→ GitHub Actions triggered (.github/workflows/ci-backend.yaml)
               │
               ├─→ Lint & Test (ruff, pytest)
               │
               ├─→ Build Docker image
               │   └─→ Tag: sha-<commit-hash>
               │
               ├─→ Scan Trivy (security)
               │
               ├─→ Push to Artifact Registry
               │   └─→ northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend:sha-XXXXXXX
               │
               └─→ Update shopflow-gitops repo
                   └─→ envs/staging/values-staging.yaml (image.tag: sha-XXXXXXX)
                       │
                       └─→ git push shopflow-gitops main
                           │
                           └─→ ArgoCD detects change (poll every 3 min)
                               │
                               ├─→ Helm template render
                               │
                               ├─→ Diff calculation (Git vs Cluster)
                               │
                               └─→ Auto-sync to shopflow-staging namespace
                                   │
                                   └─→ kubectl apply (Helm manifests)
                                       │
                                       └─→ Pods recreated with new image
                                           └─→ DEPLOYMENT COMPLETE (~2-5 min total)

2. PROMOTION STAGING → PROD
   └─→ Validation en staging (tests passed, stable)
       │
       └─→ Create PR in shopflow-gitops
           └─→ Modify envs/prod/values-prod.yaml (image.tag: sha-XXXXXXX)
               │
               └─→ Code review + approval
                   │
                   └─→ Merge to main
                       │
                       └─→ ArgoCD detects change
                           │
                           └─→ Auto-sync to shopflow-prod namespace
                               │
                               └─→ PROMOTION COMPLETE
```

### 7.4 Points d'intégration clés

**GitHub Actions ↔ GCP (Artifact Registry)**
- Authentification via `GCP_SA_KEY` secret
- Push image vers `northamerica-northeast2-docker.pkg.dev`

**GitHub Actions ↔ shopflow-gitops (Update)**
- Authentification via `GITOPS_PAT` secret
- Push changement dans `envs/staging/values-staging.yaml`

**ArgoCD ↔ shopflow-gitops (Watch)**
- Source repository: `https://github.com/oderbel-DS/shopflow-gitops.git`
- Branch: `main`
- Polling interval: 3 minutes (configurable)

**ArgoCD ↔ GKE Cluster**
- Applique les Helm manifests rendus
- Reconciliation: 30 secondes (configurable)

**GKE Cluster ↔ Artifact Registry**
- Fetch images avec service account credentials
- ImagePullSecret: `gcr-json-key`

---

## 🧹 Étape 8 : Nettoyage du projet

### 8.1 Script officiel de nettoyage

Le script de nettoyage est disponible dans le repo applicatif à cet emplacement :

- `shopflow/scripts/cleanup-script.sh`

**Rôle du script :**
- Génère un backup cluster (`kubectl get all -A -o yaml`)
- Supprime les pods `Failed` et `Succeeded`
- Supprime les jobs terminés (`shopflow-staging`, `shopflow-prod`)
- Nettoie les anciens tags d'images dans Artifact Registry (backend/frontend)
- Lance un nettoyage Git local sur `shopflow-gitops` si présent

### 8.2 Exécution du script

```bash
cd shopflow
chmod +x scripts/cleanup-script.sh
./scripts/cleanup-script.sh
```

### 8.3 Mode simulation (recommandé avant production)

```bash
cd shopflow
DRY_RUN=true ./scripts/cleanup-script.sh
```

### 8.4 Paramètres utiles

```bash
# Garder 10 tags au lieu de 15
KEEP_TAGS=10 ./scripts/cleanup-script.sh

# Forcer un contexte kubectl spécifique
KUBECONFIG_CONTEXT=gke_shopflow-499020_northamerica-northeast2_shopflow-cluster \
./scripts/cleanup-script.sh
```

### 8.5 Vérifications après nettoyage

```bash
# Vérifier les pods
kubectl get pods -A

# Vérifier les jobs
kubectl get jobs -n shopflow-staging
kubectl get jobs -n shopflow-prod

# Vérifier les tags restants
gcloud artifacts docker tags list \
  northamerica-northeast2-docker.pkg.dev/shopflow-499020/shopflow/backend \
  --sort-by=~UPDATE_TIME --limit=20
```

### 8.6 Notes de sécurité

- Lancer d'abord en `DRY_RUN=true` sur un environnement sensible
- Ne pas exécuter pendant une fenêtre de forte charge
- Conserver les backups générés dans `shopflow/backups/`

---

## 🔍 Références rapides et ressources

### Liens utiles

- **GCP Console** : https://console.cloud.google.com/
- **Artifact Registry** : https://console.cloud.google.com/artifacts
- **GKE Clusters** : https://console.cloud.google.com/kubernetes/clusters
- **GitHub Repo applicatif** : https://github.com/oderbel-DS/shopflow
- **GitHub Repo GitOps** : https://github.com/oderbel-DS/shopflow-gitops
- **GitHub Actions (CI)** : https://github.com/oderbel-DS/shopflow/actions
- **ArgoCD Local** : `kubectl port-forward -n argocd svc/argocd-server 8080:80` → http://localhost:8080
- **Grafana Local** : `kubectl port-forward -n monitoring svc/kps-grafana 3000:80` → http://localhost:3000
- **Prometheus Local** : `kubectl port-forward -n monitoring svc/kps-prometheus 9090:9090` → http://localhost:9090

### Documentation externalisée

- **Kubernetes official docs** : https://kubernetes.io/docs/
- **Helm documentation** : https://helm.sh/docs/
- **ArgoCD documentation** : https://argo-cd.readthedocs.io/
- **GKE best practices** : https://cloud.google.com/kubernetes-engine/docs/best-practices
- **Artifact Registry** : https://cloud.google.com/artifact-registry/docs
- **kube-prometheus-stack** : https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack

### Outils recommandés

**CLI Tools:**
- `kubectl` : Interaction Kubernetes
- `helm` : Package management Kubernetes
- `gcloud` : Google Cloud administration
- `git` : Version control
- `argocd` : ArgoCD CLI (optionnel, kubectl suffit)

**Terminal Tools:**
- `jq` : JSON parsing and manipulation
- `yq` : YAML parsing and manipulation
- `watch` : Monitor command output in real-time

```bash
# Installer les outils (MacOS avec Homebrew)
brew install kubectl helm gcloud git jq yq

# Installer les outils (Linux)
curl https://sdk.cloud.google.com | bash  # gcloud
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash  # helm
apt-get install -y kubectl jq yq  # kubectl, jq, yq
```

### Configuration rapide initiale

```bash
# === Setup initial (une seule fois) ===

# 1. Authentifier GCloud
gcloud auth login
gcloud config set project shopflow-499020
gcloud config set compute/region northamerica-northeast2

# 2. Récupérer les kubeconfig credentials
gcloud container clusters get-credentials shopflow-cluster --region northamerica-northeast2

# 3. Vérifier la connexion
kubectl cluster-info
kubectl get nodes

# 4. Cloner les repos
git clone https://github.com/oderbel-DS/shopflow.git
git clone https://github.com/oderbel-DS/shopflow-gitops.git

# 5. Test du workflow complet
# - Modifier un fichier dans shopflow/backend
# - git push → déclenche CI
# - Voir le déploiement en staging (~2-5 min)
```

---

## 🎯 Checklist de déploiement

### Pre-deployment

- [ ] Cluster GKE créé et accessible (`gcloud container clusters get-credentials`)
- [ ] Namespaces créés (`kubectl apply -f bootstrap/namespaces.yaml`)
- [ ] Plateforme installée (Ingress, Monitoring, ArgoCD)
- [ ] Secrets GitHub configurés (GCP_PROJECT, GCP_SA_KEY, GITOPS_PAT)
- [ ] Deux repos clonés localement (shopflow, shopflow-gitops)

### Deployment

- [ ] Commit + push dans shopflow
- [ ] GitHub Actions déclenché et réussi (voir actions/)
- [ ] Image publiée dans Artifact Registry
- [ ] shopflow-gitops/envs/staging/values-staging.yaml mis à jour
- [ ] ArgoCD a synced la staging (attendre 3-5 min)
- [ ] Pods en état Running dans shopflow-staging namespace
- [ ] Application accessible via Ingress

### Post-deployment

- [ ] Logs de staging vérifiés (pas d'erreurs)
- [ ] Tests d'intégration passent (si appliquable)
- [ ] Métriques Prometheus récoltées (voir Grafana)
- [ ] Prêt pour la promotion vers production

### Production promotion

- [ ] Validation complète en staging
- [ ] PR créée dans shopflow-gitops (envs/prod/values-prod.yaml)
- [ ] Code review + approval
- [ ] PR mergée dans main
- [ ] ArgoCD a synced la prod (attendre 3-5 min)
- [ ] Pods en état Running dans shopflow-prod namespace
- [ ] Déploiement production vérifié

---

**Version du guide:** 1.0  
**Dernière révision:** Juin 2026  
**Mainteneur:** DevOps Team ShopFlow  
**Support:** Pour les questions ou corrections, créer une issue dans les repos GitHub
