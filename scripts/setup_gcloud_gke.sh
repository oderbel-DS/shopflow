#!/usr/bin/env bash
set -euo pipefail

# ShopFlow bootstrap: install gcloud CLI, configure project, create GKE cluster,
# configure Artifact Registry, and validate kubectl connectivity.

REGION="northamerica-northeast1"
ZONE="northamerica-northeast1-a"
CLUSTER="shopflow-cluster"
REPO="shopflow"
NODES="2"
MACHINE_TYPE="e2-standard-2"
SKIP_INSTALL="false"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -p, --project-id <id>      GCP project ID (if omitted, interactive prompt)
  -r, --region <region>      GCP region (default: $REGION)
  -z, --zone <zone>          GCP zone (default: $ZONE)
  -c, --cluster <name>       GKE cluster name (default: $CLUSTER)
  -a, --repo <name>          Artifact Registry repo name (default: $REPO)
  -n, --nodes <count>        Number of GKE nodes (default: $NODES)
  -m, --machine <type>       GKE machine type (default: $MACHINE_TYPE)
      --skip-install         Skip gcloud CLI installation step
  -h, --help                 Show this help

Examples:
  $0
  $0 --project-id my-gcp-project
  $0 --project-id my-gcp-project --cluster shopflow-prod --nodes 3
EOF
}

PROJECT_ID="${PROJECT_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -z|--zone)
      ZONE="$2"
      shift 2
      ;;
    -c|--cluster)
      CLUSTER="$2"
      shift 2
      ;;
    -a|--repo)
      REPO="$2"
      shift 2
      ;;
    -n|--nodes)
      NODES="$2"
      shift 2
      ;;
    -m|--machine)
      MACHINE_TYPE="$2"
      shift 2
      ;;
    --skip-install)
      SKIP_INSTALL="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  read -rp "Enter your GCP PROJECT_ID: " PROJECT_ID
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "PROJECT_ID is required."
  exit 1
fi

install_gcloud() {
  echo "==> Installing gcloud CLI and GKE auth plugin"
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin
}

if [[ "$SKIP_INSTALL" == "false" ]]; then
  install_gcloud
else
  echo "==> Skipping gcloud installation (--skip-install)"
fi

echo "==> gcloud version"
gcloud version

echo "==> Login (browser flow may open)"
gcloud auth login

echo "==> Configuring project and defaults"
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

echo "==> Enabling required services"
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com

echo "==> Creating GKE cluster if missing"
if gcloud container clusters describe "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  echo "Cluster '$CLUSTER' already exists in region '$REGION'."
else
  gcloud container clusters create "$CLUSTER" \
    --region "$REGION" \
    --num-nodes "$NODES" \
    --machine-type "$MACHINE_TYPE"
fi

echo "==> Fetching kubectl credentials"
gcloud container clusters get-credentials "$CLUSTER" --region "$REGION"

echo "==> Creating Artifact Registry repo if missing"
if gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1; then
  echo "Artifact Registry repo '$REPO' already exists in '$REGION'."
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="ShopFlow Docker images"
fi

echo "==> Configuring Docker auth for Artifact Registry"
gcloud auth configure-docker "${REGION}-docker.pkg.dev"

echo "==> Validation"
kubectl get nodes
gcloud container clusters list

echo "==> Done"
echo "Project: $PROJECT_ID"
echo "Region:  $REGION"
echo "Cluster: $CLUSTER"
echo "Repo:    $REPO"
