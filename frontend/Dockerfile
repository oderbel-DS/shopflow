# frontend/Dockerfile
# --- Stage 1 : build du bundle React ---
FROM node:20-alpine AS build
WORKDIR /app
COPY . .
RUN if [ -f package.json ]; then \
			if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then npm ci; else npm install; fi && npm run build; \
		else \
			mkdir -p dist && printf '%s\n' '<!doctype html><html><head><meta charset="utf-8"><title>ShopFlow Frontend</title></head><body><h1>ShopFlow frontend non initialise</h1></body></html>' > dist/index.html; \
		fi

# --- Stage 2 : service statique par Nginx ---
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
