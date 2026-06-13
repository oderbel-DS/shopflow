**ShopFlow --- Mémo des commandes pas à pas**

*Migration vers Kubernetes (GKE) · Docker · Helm · CI/CD · GitOps*

Aide-mémoire opérationnel : pour chaque étape, la plateforme où exécuter et les commandes exactes, dans l\'ordre.

**Légende des plateformes**

  ------------------------------------------------------------------------------------------------------
     **Google Cloud** --- console GCP / Cloud Shell (icône \>\_ en haut à droite, rien à installer).
  -- ---------------------------------------------------------------------------------------------------
     **Terminal kubectl / Helm** --- dans Cloud Shell (recommandé) ou en local si le SDK est installé.

     **ArgoCD** --- CLI argocd ou interface web d\'ArgoCD.

     **GitHub** --- site github.com (interface web) ou commandes git dans le terminal.
  ------------------------------------------------------------------------------------------------------

## Structure des dossiers du projet

Avant de commencer, voici la carte complète du projet, fichier par fichier --- gardez-la sous les yeux pour savoir où ranger chaque fichier que vous créez. On travaille avec DEUX dépôts : le code (application) et le GitOps (ce qu\'ArgoCD déploie).

+-----------------------------------------------------------------------+
| **PLATEFORME : Terminal (créer le squelette de dossiers)**            |
+=======================================================================+
| \# À la racine du dépôt shopflow/                                     |
|                                                                       |
| mkdir -p backend frontend chart/templates \\                          |
|                                                                       |
| bootstrap/quotas bootstrap/platform bootstrap/network-policies \\     |
|                                                                       |
| .github/workflows                                                     |
+-----------------------------------------------------------------------+

**Dépôt applicatif** shopflow/ :

+-----------------------------------------------------------------------+
| shopflow/ \# DEPOT APPLICATIF (le code)                               |
|                                                                       |
| \|\-- README.md                                                       |
|                                                                       |
| \|\-- .gitignore \# IMPORTANT : doit contenir key.json                |
|                                                                       |
| \|                                                                    |
|                                                                       |
| \|\-- backend/ \# code source du backend                              |
|                                                                       |
| \| └── Dockerfile \# build multi-stage                                |
|                                                                       |
| \|\-- frontend/ \# code source du frontend (React)                    |
|                                                                       |
| \| └── Dockerfile \# build React -\> Nginx                            |
|                                                                       |
| \|                                                                    |
|                                                                       |
| \|\-- chart/ \# Helm Chart de l\'application                          |
|                                                                       |
| \| \|\-- Chart.yaml                                                   |
|                                                                       |
| \| \|\-- values.yaml                                                  |
|                                                                       |
| \| └── templates/                                                     |
|                                                                       |
| \| \|\-- \_helpers.tpl                                                |
|                                                                       |
| \| \|\-- deployment.yaml                                              |
|                                                                       |
| \| \|\-- service.yaml                                                 |
|                                                                       |
| \| \|\-- configmap.yaml                                               |
|                                                                       |
| \| \|\-- secret.yaml                                                  |
|                                                                       |
| \| \|\-- ingress.yaml                                                 |
|                                                                       |
| \| └── hpa.yaml                                                       |
|                                                                       |
| \|                                                                    |
|                                                                       |
| \|\-- bootstrap/ \# a appliquer UNE FOIS (kubectl / helm)             |
|                                                                       |
| \| \|\-- namespaces.yaml \# \<\-- les 5 namespaces du projet          |
|                                                                       |
| \| \|\-- quotas/                                                      |
|                                                                       |
| \| \| \|\-- resourcequota-dev.yaml                                    |
|                                                                       |
| \| \| └── limitrange-dev.yaml                                         |
|                                                                       |
| \| \|\-- platform/ \# values des charts Helm                          |
|                                                                       |
| \| \| \|\-- values-ingress.yaml                                       |
|                                                                       |
| \| \| \|\-- values-monitoring.yaml                                    |
|                                                                       |
| \| \| └── values-argocd.yaml                                          |
|                                                                       |
| \| └── network-policies/ \# Zero-Trust                                |
|                                                                       |
| \| \|\-- np-default-deny.yaml                                         |
|                                                                       |
| \| \|\-- np-frontend.yaml                                             |
|                                                                       |
| \| \|\-- np-backend.yaml                                              |
|                                                                       |
| \| \|\-- np-database.yaml                                             |
|                                                                       |
| \| └── np-egress-dns.yaml                                             |
|                                                                       |
| \|                                                                    |
|                                                                       |
| └── .github/workflows/                                                |
|                                                                       |
| \|\-- ci.yaml \# CI backend                                           |
|                                                                       |
| └── ci-frontend.yaml \# CI frontend                                   |
+=======================================================================+
+-----------------------------------------------------------------------+

**Dépôt GitOps** shopflow-gitops/ (créé à l\'Étape 4 / déployé à l\'Étape 9) :

+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| shopflow-gitops/ \# DEPOT GITOPS (ce qu\'ArgoCD surveille)                                                                                                                                                                                                                     |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| \|\-- apps/ \# Applications ArgoCD (App-of-Apps)                                                                                                                                                                                                                               |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| \| \|\-- root-app.yaml                                                                                                                                                                                                                                                         |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| \| \|\-- shopflow-staging.yaml                                                                                                                                                                                                                                                 |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| \| └── shopflow-prod.yaml                                                                                                                                                                                                                                                      |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| └── envs/                                                                                                                                                                                                                                                                      |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| \|\-- staging/                                                                                                                                                                                                                                                                 |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| \| └── values-staging.yaml \# tag bumpe AUTO par la CI                                                                                                                                                                                                                         |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| └── prod/                                                                                                                                                                                                                                                                      |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| └── values-prod.yaml \# tag promu A LA MAIN                                                                                                                                                                                                                                    |                                                                      |
+================================================================================================================================================================================================================================================================================+======================================================================+
| **La règle simple pour ranger chaque fichier**                                                                                                                                                                                                                                 |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| Une seule question : **un humain l\'applique une fois à la main, ou ArgoCD le déploie en continu ?**                                                                                                                                                                           |                                                                      |
|                                                                                                                                                                                                                                                                                |                                                                      |
| Le socle (namespaces, plateforme Helm, network policies, quotas) → bootstrap/ du dépôt app. L\'application et ses tags d\'image par environnement → dépôt gitops. La CI fait le pont (elle vit dans le dépôt app, construit l\'image, puis écrit le tag dans le dépôt gitops). |                                                                      |
+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 0 --- Choisir où taper les commandes

  -----------------------------------------------------------------------
  **PLATEFORME : Google Cloud --- Cloud Shell (recommandé)**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Ouvrez la console GCP puis cliquez sur l\'icône Terminal « \>\_ » en haut à droite. gcloud et kubectl y sont déjà installés et authentifiés --- rien à installer. Tout le TP peut se faire ici.

+--------------------------------------------------------------------------------------------------------------------------------------------------------------+
| **Astuce débutant**                                                                                                                                          |
|                                                                                                                                                              |
| Si une commande échoue, relisez le message en entier : 9 fois sur 10 il indique précisément la cause (projet non défini, API non activée, droits manquants). |
+==============================================================================================================================================================+
+--------------------------------------------------------------------------------------------------------------------------------------------------------------+

## Étape 1 --- Créer le dépôt Git applicatif

  -----------------------------------------------------------------------
  **PLATEFORME : GitHub (créer un repo vide) + Terminal (git)**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Créez d\'abord un dépôt VIDE sur github.com (bouton New), puis dans le terminal :

+----------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| mkdir shopflow && cd shopflow                                                                                                                |                                                                      |
|                                                                                                                                              |                                                                      |
| git init                                                                                                                                     |                                                                      |
|                                                                                                                                              |                                                                      |
| echo \"# ShopFlow --- Projet fil rouge K8s\" \> README.md                                                                                    |                                                                      |
|                                                                                                                                              |                                                                      |
| git add .                                                                                                                                    |                                                                      |
|                                                                                                                                              |                                                                      |
| git commit -m \"chore: initialisation du projet ShopFlow\"                                                                                   |                                                                      |
|                                                                                                                                              |                                                                      |
| \# Relier à GitHub (remplacez VOTRE_COMPTE)                                                                                                  |                                                                      |
|                                                                                                                                              |                                                                      |
| git remote add origin https://github.com/VOTRE_COMPTE/shopflow.git                                                                           |                                                                      |
|                                                                                                                                              |                                                                      |
| git branch -M main                                                                                                                           |                                                                      |
|                                                                                                                                              |                                                                      |
| git push -u origin main                                                                                                                      |                                                                      |
+==============================================================================================================================================+======================================================================+
| **Si « author identity unknown »**                                                                                                           |                                                                      |
|                                                                                                                                              |                                                                      |
| Configurez votre identité une fois : git config \--global user.name \"Votre Nom\" puis git config \--global user.email \"vous@exemple.com\". |                                                                      |
+----------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 2 --- Créer le cluster GKE

+-----------------------------------------------------------------------+
| **PLATEFORME : Google Cloud (Cloud Shell)**                           |
+=======================================================================+
| \# 1. Sélectionner le projet et la région (Toronto)                   |
|                                                                       |
| gcloud config set project VOTRE_PROJECT_ID                            |
|                                                                       |
| gcloud config set compute/region northamerica-northeast2              |
|                                                                       |
| \# 2. Activer les API nécessaires                                     |
|                                                                       |
| gcloud services enable container.googleapis.com \\                    |
|                                                                       |
| artifactregistry.googleapis.com compute.googleapis.com                |
|                                                                       |
| \# 3. Créer le cluster (autoscaling 1-\>3 noeuds)                     |
|                                                                       |
| gcloud container clusters create shopflow-cluster \\                  |
|                                                                       |
| \--region northamerica-northeast2 \\                                  |
|                                                                       |
| \--num-nodes 1 \--machine-type e2-standard-2 \\                       |
|                                                                       |
| \--enable-autoscaling \--min-nodes 1 \--max-nodes 3 \\                |
|                                                                       |
| \--release-channel regular \--enable-ip-alias \\                      |
|                                                                       |
| \--enable-dataplane-v2 \# requis pour les Network Policies (Étape 11) |
|                                                                       |
| \# 4. Configurer kubectl pour ce cluster                              |
|                                                                       |
| gcloud container clusters get-credentials shopflow-cluster \\         |
|                                                                       |
| \--region northamerica-northeast2                                     |
|                                                                       |
| \# 5. Vérifier                                                        |
|                                                                       |
| kubectl get nodes -o wide                                             |
|                                                                       |
| kubectl cluster-info                                                  |
+-----------------------------------------------------------------------+

## Étape 3 --- Créer les namespaces

  -----------------------------------------------------------------------
  **PLATEFORME : Terminal kubectl**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Déclarez les namespaces dans un fichier versionné namespaces.yaml (dev / staging / production / monitoring / argocd), puis :

+-----------------------------------------------------------------------+
| kubectl apply -f namespaces.yaml                                      |
|                                                                       |
| kubectl get ns \--show-labels                                         |
+=======================================================================+
+-----------------------------------------------------------------------+

## Étape 4 --- Prérequis CI/CD (à faire une seule fois)

  -----------------------------------------------------------------------
  **PLATEFORME : Google Cloud + GitHub + ArgoCD**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

**4a. Dépôt d\'images Artifact Registry ---** Google Cloud

+-----------------------------------------------------------------------+
| gcloud artifacts repositories create shopflow \\                      |
|                                                                       |
| \--repository-format=docker \\                                        |
|                                                                       |
| \--location=northamerica-northeast2 \\                                |
|                                                                       |
| \--description=\"Images du projet ShopFlow\"                          |
|                                                                       |
| gcloud artifacts repositories list                                    |
+=======================================================================+
+-----------------------------------------------------------------------+

**4b. Compte de service + droits + clé JSON ---** Google Cloud

+--------------------------------------------------------------------------------+
| gcloud iam service-accounts create ci-shopflow \\                              |
|                                                                                |
| \--display-name=\"CI ShopFlow (GitHub Actions)\"                               |
|                                                                                |
| gcloud projects add-iam-policy-binding PROJECT_ID \\                           |
|                                                                                |
| \--member=\"serviceAccount:ci-shopflow@PROJECT_ID.iam.gserviceaccount.com\" \\ |
|                                                                                |
| \--role=\"roles/artifactregistry.writer\"                                      |
|                                                                                |
| gcloud iam service-accounts keys create key.json \\                            |
|                                                                                |
| \--iam-account=ci-shopflow@PROJECT_ID.iam.gserviceaccount.com                  |
+================================================================================+
+--------------------------------------------------------------------------------+

**4c. Secrets GitHub ---** GitHub (dépôt → Settings → Secrets and variables → Actions → New repository secret)

+---------------------------------------------------------------------------------------------------------------------------+
| **Trois secrets à créer**                                                                                                 |
|                                                                                                                           |
| **GCP_PROJECT** : l\'ID du projet GCP.                                                                                    |
|                                                                                                                           |
| **GCP_SA_KEY** : tout le contenu du fichier key.json (copier-coller le JSON entier).                                      |
|                                                                                                                           |
| **GITOPS_PAT** : un Personal Access Token GitHub (scope repo) --- Settings → Developer settings → Personal access tokens. |
+===========================================================================================================================+
+---------------------------------------------------------------------------------------------------------------------------+

**4d. Connecter ArgoCD au dépôt GitOps (si privé) ---** ArgoCD

+----------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| argocd repo add https://github.com/mon-org/shopflow-gitops.git \\                                        |                                                                      |
|                                                                                                          |                                                                      |
| \--username votre-login-github \--password VOTRE_PAT                                                     |                                                                      |
|                                                                                                          |                                                                      |
| argocd repo list                                                                                         |                                                                      |
+==========================================================================================================+======================================================================+
| **Production : pas de clé JSON**                                                                         |                                                                      |
|                                                                                                          |                                                                      |
| En entreprise, préférez Workload Identity Federation (sans clé). Et ajoutez key.json à votre .gitignore. |                                                                      |
+----------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 5 --- Installer la plateforme via Helm

  -----------------------------------------------------------------------
  **PLATEFORME : Terminal Helm / kubectl**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Ordre impératif : Ingress-NGINX → Metrics Server → kube-prometheus-stack → ArgoCD. Chaque composant a son values.yaml versionné dans Git.

+---------------------------------------------------------------------------------------+
| \# 5.1 Ingress-NGINX (point d\'entrée HTTP/S, crée un Load Balancer GCP)              |
|                                                                                       |
| helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx                |
|                                                                                       |
| helm repo update                                                                      |
|                                                                                       |
| helm install ingress-nginx ingress-nginx/ingress-nginx \\                             |
|                                                                                       |
| \--namespace ingress-nginx \--create-namespace -f values-ingress.yaml                 |
|                                                                                       |
| kubectl get svc -n ingress-nginx ingress-nginx-controller \# attendre l\'EXTERNAL-IP  |
|                                                                                       |
| \# 5.2 Metrics Server (déjà présent sur GKE --- vérifier d\'abord)                    |
|                                                                                       |
| kubectl top nodes \# s\'il répond, Metrics Server est actif                           |
|                                                                                       |
| \# 5.3 kube-prometheus-stack (Prometheus + Grafana + Alertmanager)                    |
|                                                                                       |
| helm repo add prometheus-community https://prometheus-community.github.io/helm-charts |
|                                                                                       |
| helm repo update                                                                      |
|                                                                                       |
| helm install kps prometheus-community/kube-prometheus-stack \\                        |
|                                                                                       |
| \--namespace monitoring \--create-namespace -f values-monitoring.yaml                 |
|                                                                                       |
| \# 5.4 ArgoCD                                                                         |
|                                                                                       |
| helm repo add argo https://argoproj.github.io/argo-helm                               |
|                                                                                       |
| helm repo update                                                                      |
|                                                                                       |
| helm install argocd argo/argo-cd \\                                                   |
|                                                                                       |
| \--namespace argocd \--create-namespace -f values-argocd.yaml                         |
+=======================================================================================+
+---------------------------------------------------------------------------------------+

## Étape 6 --- Accéder à ArgoCD

+-----------------------------------------------------------------------+
| **PLATEFORME : Terminal kubectl + ArgoCD (UI)**                       |
+=======================================================================+
| kubectl get pods -n argocd                                            |
|                                                                       |
| \# Mot de passe admin initial                                         |
|                                                                       |
| kubectl -n argocd get secret argocd-initial-admin-secret \\           |
|                                                                       |
| -o jsonpath=\'{.data.password}\' \| base64 -d ; echo                  |
|                                                                       |
| \# Ouvrir l\'UI (puis http://localhost:8080, user: admin)             |
|                                                                       |
| kubectl -n argocd port-forward svc/argocd-server 8080:80              |
+-----------------------------------------------------------------------+

## Étape 7 --- (Option) Premier build manuel de l\'image

  -----------------------------------------------------------------------
  **PLATEFORME : Terminal Docker + Artifact Registry**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

En temps normal c\'est la CI (Étape 8) qui construit l\'image. Pour un premier test manuel :

+------------------------------------------------------------------------------+
| \# Autoriser Docker à pousser vers Artifact Registry                         |
|                                                                              |
| gcloud auth configure-docker northamerica-northeast2-docker.pkg.dev \--quiet |
|                                                                              |
| \# Construire, taguer (avec le SHA git) et pousser                           |
|                                                                              |
| REPO=northamerica-northeast2-docker.pkg.dev/PROJECT_ID/shopflow              |
|                                                                              |
| docker build -t \$REPO/backend:sha-\$(git rev-parse \--short HEAD) ./backend |
|                                                                              |
| docker push \$REPO/backend:sha-\$(git rev-parse \--short HEAD)               |
+==============================================================================+
+------------------------------------------------------------------------------+

## Étape 8 --- Déclencher le pipeline CI

  -----------------------------------------------------------------------
  **PLATEFORME : GitHub (Actions) + git**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Le workflow .github/workflows/ci.yaml se déclenche à chaque push sur main touchant backend/\*\* (idem ci-frontend.yaml pour frontend/\*\*). Pour le lancer :

+-----------------------------------------------------------------------+
| git add .                                                             |
|                                                                       |
| git commit -m \"feat: nouvelle version backend\"                      |
|                                                                       |
| git push                                                              |
+=======================================================================+
+-----------------------------------------------------------------------+

**Observer le run :** sur github.com, onglet **Actions** → cliquez sur le run en cours pour voir les logs de chaque job (test → build-push → bump-gitops). En cas d\'échec, le job rouge indique l\'étape fautive ; bouton **Re-run jobs** pour relancer.

+------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| **Ce que fait la CI (et ne fait pas)**                                                                                                                                 |
|                                                                                                                                                                        |
| Elle construit, scanne (Trivy), pousse l\'image, puis met à jour le tag dans le dépôt GitOps. Elle ne fait JAMAIS kubectl apply : c\'est ArgoCD qui déploie (Étape 9). |
+========================================================================================================================================================================+
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

## Étape 9 --- Déployer via ArgoCD (GitOps)

+----------------------------------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| **PLATEFORME : kubectl + ArgoCD**                                                                                                                                    |                                                                      |
+======================================================================================================================================================================+======================================================================+
| \# Déclarer l\'Application (une fois)                                                                                                                                |                                                                      |
|                                                                                                                                                                      |                                                                      |
| kubectl apply -f apps/shopflow-staging.yaml                                                                                                                          |                                                                      |
|                                                                                                                                                                      |                                                                      |
| \# Suivre / synchroniser                                                                                                                                             |                                                                      |
|                                                                                                                                                                      |                                                                      |
| argocd app list                                                                                                                                                      |                                                                      |
|                                                                                                                                                                      |                                                                      |
| argocd app get shopflow-staging                                                                                                                                      |                                                                      |
|                                                                                                                                                                      |                                                                      |
| argocd app sync shopflow-staging \# sync manuel (sinon automatique)                                                                                                  |                                                                      |
+----------------------------------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| **Démo self-heal**                                                                                                                                                   |                                                                      |
|                                                                                                                                                                      |                                                                      |
| Provoquez un drift : kubectl -n staging scale deploy shopflow-shopflow \--replicas=7. Avec selfHeal, ArgoCD ré-applique l\'état Git et revient à la valeur déclarée. |                                                                      |
+----------------------------------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 10 --- Autoscaling & haute disponibilité

+----------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| **PLATEFORME : Terminal kubectl**                                                                                    |                                                                      |
+======================================================================================================================+======================================================================+
| \# Le HPA est généré par le Helm Chart. Vérifier :                                                                   |                                                                      |
|                                                                                                                      |                                                                      |
| kubectl get hpa -n production                                                                                        |                                                                      |
|                                                                                                                      |                                                                      |
| kubectl describe hpa shopflow -n production                                                                          |                                                                      |
|                                                                                                                      |                                                                      |
| \# Test de charge pour déclencher le scale-up (ex. hey)                                                              |                                                                      |
|                                                                                                                      |                                                                      |
| hey -z 2m -c 50 http://\<EXTERNAL-IP\>/                                                                              |                                                                      |
|                                                                                                                      |                                                                      |
| kubectl get hpa -n production -w \# observer la montée en réplicas                                                   |                                                                      |
|                                                                                                                      |                                                                      |
| \# Haute dispo : vérifier le PodDisruptionBudget                                                                     |                                                                      |
|                                                                                                                      |                                                                      |
| kubectl get pdb -n production                                                                                        |                                                                      |
+----------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| **Rappel n°1 du TP**                                                                                                 |                                                                      |
|                                                                                                                      |                                                                      |
| Sans requests.cpu défini, le HPA en mode Utilization ne peut pas se déclencher. Toujours définir requests ET limits. |                                                                      |
+----------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 11 --- Sécurisation réseau (Network Policies)

  -----------------------------------------------------------------------
  **PLATEFORME : Terminal kubectl**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Modèle Zero-Trust : on refuse tout, puis on autorise flux par flux (Ingress → Frontend → Backend → Database, sans oublier l\'Egress DNS).

+-----------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| \# 1. Tout refuser par défaut dans le namespace                                                                                   |                                                                      |
|                                                                                                                                   |                                                                      |
| kubectl apply -f np-default-deny.yaml                                                                                             |                                                                      |
|                                                                                                                                   |                                                                      |
| \# 2. Autoriser le parcours légitime + le DNS                                                                                     |                                                                      |
|                                                                                                                                   |                                                                      |
| kubectl apply -f np-frontend.yaml                                                                                                 |                                                                      |
|                                                                                                                                   |                                                                      |
| kubectl apply -f np-backend.yaml                                                                                                  |                                                                      |
|                                                                                                                                   |                                                                      |
| kubectl apply -f np-database.yaml                                                                                                 |                                                                      |
|                                                                                                                                   |                                                                      |
| kubectl apply -f np-egress-dns.yaml                                                                                               |                                                                      |
|                                                                                                                                   |                                                                      |
| \# 3. Vérifier                                                                                                                    |                                                                      |
|                                                                                                                                   |                                                                      |
| kubectl get networkpolicy -n production                                                                                           |                                                                      |
+===================================================================================================================================+======================================================================+
| **Prérequis cluster**                                                                                                             |                                                                      |
|                                                                                                                                   |                                                                      |
| Les NetworkPolicies ne s\'appliquent que si Dataplane V2 (ou Calico) est actif --- d\'où le \--enable-dataplane-v2 de l\'Étape 2. |                                                                      |
+-----------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 12 --- Promouvoir staging → production

  -----------------------------------------------------------------------
  **PLATEFORME : git (dépôt GitOps) + ArgoCD**
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Promouvoir = rejouer la MÊME image validée en staging. On recopie le tag, on commit, ArgoCD déploie.

+-----------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| cd shopflow-gitops                                                                                                                |                                                                      |
|                                                                                                                                   |                                                                      |
| grep \"tag:\" envs/staging/values-staging.yaml \# ex. tag: sha-1a2b3c                                                             |                                                                      |
|                                                                                                                                   |                                                                      |
| sed -i \"s\|tag:.\*\|tag: sha-1a2b3c\|\" envs/prod/values-prod.yaml                                                               |                                                                      |
|                                                                                                                                   |                                                                      |
| git commit -am \"promote(prod): sha-1a2b3c (validé en staging)\"                                                                  |                                                                      |
|                                                                                                                                   |                                                                      |
| git push                                                                                                                          |                                                                      |
+===================================================================================================================================+======================================================================+
| **Garde-fous prod**                                                                                                               |                                                                      |
|                                                                                                                                   |                                                                      |
| Jamais de tag non testé. Idéalement, passez par une Pull Request (revue à deux yeux) ou un sync manuel ArgoCD pour la production. |                                                                      |
+-----------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Étape 13 --- Nettoyage (fin de séance)

+------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| **PLATEFORME : Google Cloud**                                                                        |                                                                      |
+======================================================================================================+======================================================================+
| **Évitez la facturation résiduelle**                                                                 |                                                                      |
|                                                                                                      |                                                                      |
| Si vous avez créé un vrai cluster GKE, supprimez-le en fin de séance, sinon il continue de facturer. |                                                                      |
+------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+
| \# (Optionnel) supprimer les releases applicatives                                                   |                                                                      |
|                                                                                                      |                                                                      |
| helm uninstall shopflow -n production                                                                |                                                                      |
|                                                                                                      |                                                                      |
| \# Supprimer le cluster GKE                                                                          |                                                                      |
|                                                                                                      |                                                                      |
| gcloud container clusters delete shopflow-cluster \\                                                 |                                                                      |
|                                                                                                      |                                                                      |
| \--region northamerica-northeast2 \--quiet                                                           |                                                                      |
|                                                                                                      |                                                                      |
| \# (Optionnel) supprimer le dépôt d\'images                                                          |                                                                      |
|                                                                                                      |                                                                      |
| gcloud artifacts repositories delete shopflow \\                                                     |                                                                      |
|                                                                                                      |                                                                      |
| \--location northamerica-northeast2 \--quiet                                                         |                                                                      |
+------------------------------------------------------------------------------------------------------+----------------------------------------------------------------------+

## Récapitulatif --- qui fait quoi, où

  -----------------------------------------------------------------------
  **Étape**                                  **Plateforme**
  ------------------------------------------ ----------------------------
  0 · Choisir le terminal                    Google Cloud (Cloud Shell)

  1 · Dépôt Git applicatif                   GitHub + git

  2 · Cluster GKE                            Google Cloud

  3 · Namespaces                             kubectl

  4 · Prérequis CI/CD                        GCP + GitHub + ArgoCD

  5 · Plateforme (Helm)                      Helm / kubectl

  6 · Accès ArgoCD                           kubectl + ArgoCD

  7 · Build manuel (option)                  Docker + Artifact Registry

  8 · Pipeline CI                            GitHub Actions

  9 · Déploiement GitOps                     kubectl + ArgoCD

  10 · Autoscaling & HA                      kubectl

  11 · Network Policies                      kubectl

  12 · Promotion prod                        git (GitOps) + ArgoCD

  13 · Nettoyage                             Google Cloud
  -----------------------------------------------------------------------

*DevPilot.ca · Formation Docker & Kubernetes --- Formateur : Oussama Derbel*
