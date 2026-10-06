# syntax=docker/dockerfile:1

# ---- build ----
FROM node:24-alpine AS build
WORKDIR /src

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npx ng build --configuration production

# ---- runtime ----
# nginx-unprivileged runs as a non-root user and listens on 8080.
FROM nginxinc/nginx-unprivileged:1.30-alpine

# The official nginx entrypoint renders /etc/nginx/templates/*.template with envsubst at startup,
# which is how runtime settings (API upstream, config.json values) get into the image.
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY nginx/security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY --from=build /src/dist/web/browser /usr/share/nginx/html

ENV API_UPSTREAM=http://api:8080 \
    API_BASE_URL="" \
    APPINSIGHTS_CONNECTION_STRING="" \
    SHIPLOG_ENVIRONMENT=local

EXPOSE 8080
