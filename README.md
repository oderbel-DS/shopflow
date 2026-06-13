# ShopFlow — Projet de migration K8s

## Architecture des depots

- Ce depot contient le code applicatif (frontend + backend), les Dockerfiles et les pipelines CI.
- Le chart Helm et les manifests ArgoCD sont maintenus dans le depot `shopflow-gitops`.
- La source de verite du deploiement Kubernetes est donc `shopflow-gitops`.
