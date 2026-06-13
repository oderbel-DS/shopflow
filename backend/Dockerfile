# backend/Dockerfile
# --- Stage 1 : build des dependances dans un venv ---
FROM python:3.11-slim AS builder
WORKDIR /app
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Stage 2 : image finale, minimale ---
FROM python:3.11-slim AS runtime
WORKDIR /app
# Utilisateur non-root (securite)
RUN useradd -m -u 1001 appuser
COPY --from=builder /opt/venv /opt/venv
COPY app/ ./app/
ENV PATH="/opt/venv/bin:$PATH"
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
