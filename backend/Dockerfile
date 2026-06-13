# ---- Stage 1 : l'atelier (on installe les dépendances) ----
FROM python:3.11-slim AS builder      # image de base Python legere
WORKDIR /app                          # dossier de travail dans l'image
RUN python -m venv /opt/venv          # cree un environnement Python isole
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .               # copie la liste des dependances
RUN pip install --no-cache-dir -r requirements.txt   # les installe

# ---- Stage 2 : la boîte finale (minimale) ----
FROM python:3.11-slim AS runtime
WORKDIR /app
RUN useradd -m -u 1001 appuser        # un utilisateur NON-root (sécurité)
COPY --from=builder /opt/venv /opt/venv   # récupère SEULEMENT les dependances
COPY app/ ./app/                      # copie le code
ENV PATH="/opt/venv/bin:$PATH"
USER appuser                          # on tourne sans les droits admin
EXPOSE 8000                           # app ecoute sur le port 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
