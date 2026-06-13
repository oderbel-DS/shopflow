# backend/app/main.py
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
import os
 
app = FastAPI(title="ShopFlow API")
DB_HOST = os.getenv("DB_HOST", "localhost")
 
@app.get("/healthz")        # liveness : le process repond-il ?
def healthz(): return {"status": "ok"}
 
@app.get("/readyz")         # readiness : pret a recevoir du trafic ?
def readyz(): return {"status": "ready", "db_host": DB_HOST}
 
@app.get("/api/products")
def products(): return [{"id": 1, "name": "Clavier"}, {"id": 2, "name": "Souris"}]
 
# Expose /metrics au format Prometheus
Instrumentator().instrument(app).expose(app)
