#!/usr/bin/env bash
set -euo pipefail

# ShopFlow cleanup script
# - Creates a cluster backup
# - Deletes failed/succeeded pods
# - Deletes completed jobs
# - Keeps only the latest N image tags in Artifact Registry
# - Runs local git cleanup on shopflow-gitops if present

PROJECT_ID="shopflow-499020"
REGION="northamerica-northeast2"
REPOSITORY="shopflow"
KEEP_TAGS="${KEEP_TAGS:-15}"
KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-}"
DRY_RUN="${DRY_RUN:-false}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT_DIR}/backups"
BACKUP_FILE="${BACKUP_DIR}/cluster-backup-${TIMESTAMP}.yaml"

NAMESPACES=("shopflow-staging" "shopflow-prod")
IMAGES=("backend" "frontend")

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY_RUN: $*"
  else
    eval "$@"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Erreur: commande manquante: $1" >&2
    exit 1
  }
}

validate_keep_tags() {
  if ! [[ "${KEEP_TAGS}" =~ ^[0-9]+$ ]]; then
    echo "Erreur: KEEP_TAGS doit etre un entier positif." >&2
    exit 1
  fi
}

configure_context() {
  if [[ -n "${KUBECONFIG_CONTEXT}" ]]; then
    log "Utilisation du contexte kubectl: ${KUBECONFIG_CONTEXT}"
    run_cmd "kubectl config use-context '${KUBECONFIG_CONTEXT}'"
  fi
}

backup_cluster_state() {
  log "Creation du backup cluster: ${BACKUP_FILE}"
  run_cmd "mkdir -p '${BACKUP_DIR}'"
  run_cmd "kubectl get all -A -o yaml > '${BACKUP_FILE}'"
}

cleanup_pods() {
  log "Nettoyage pods Failed/Succeeded sur tous les namespaces"
  run_cmd "kubectl delete pods -A --field-selector=status.phase=Failed --ignore-not-found=true"
  run_cmd "kubectl delete pods -A --field-selector=status.phase=Succeeded --ignore-not-found=true"
}

cleanup_jobs() {
  for ns in "${NAMESPACES[@]}"; do
    log "Nettoyage jobs completes dans ${ns}"
    run_cmd "kubectl -n '${ns}' delete job --field-selector=status.successful=1 --ignore-not-found=true"
  done
}

cleanup_old_tags_for_image() {
  local image="$1"
  local full_image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${image}"

  log "Nettoyage des tags pour ${full_image} (garder ${KEEP_TAGS})"

  mapfile -t tags < <(
    gcloud artifacts docker tags list "${full_image}" \
      --sort-by=~UPDATE_TIME \
      --limit=999 \
      --format='value(tags)' \
      | sed '/^$/d'
  )

  if (( ${#tags[@]} <= KEEP_TAGS )); then
    log "Aucun tag a supprimer pour ${image} (tags=${#tags[@]} <= ${KEEP_TAGS})"
    return
  fi

  for tag in "${tags[@]:KEEP_TAGS}"; do
    if [[ -z "${tag}" ]]; then
      continue
    fi
    run_cmd "gcloud artifacts docker delete '${full_image}:${tag}' --delete-tags --quiet"
  done
}

cleanup_registry_tags() {
  for image in "${IMAGES[@]}"; do
    cleanup_old_tags_for_image "${image}"
  done
}

git_cleanup_if_present() {
  local gitops_dir="${ROOT_DIR}/../shopflow-gitops"
  if [[ -d "${gitops_dir}/.git" ]]; then
    log "Nettoyage git local dans ${gitops_dir}"
    run_cmd "cd '${gitops_dir}' && git fetch --prune origin && git gc --aggressive"
  else
    log "Repo shopflow-gitops non trouve a ${gitops_dir}, nettoyage git ignore"
  fi
}

main() {
  require_cmd kubectl
  require_cmd gcloud
  require_cmd git
  validate_keep_tags

  log "Debut cleanup ShopFlow"
  log "Parametres: PROJECT_ID=${PROJECT_ID}, REGION=${REGION}, REPOSITORY=${REPOSITORY}, KEEP_TAGS=${KEEP_TAGS}, DRY_RUN=${DRY_RUN}"

  configure_context
  backup_cluster_state
  cleanup_pods
  cleanup_jobs
  cleanup_registry_tags
  git_cleanup_if_present

  log "Cleanup termine avec succes"
  log "Backup genere: ${BACKUP_FILE}"
}

main "$@"
