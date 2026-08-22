# ---- build stage ----
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- runtime stage ----
# nginx-unprivileged, not nginx: the stock image starts as root to bind :80 and
# only drops its WORKERS to the nginx user. Kubernetes PodSecurity `restricted`
# rejects that outright (runAsNonRoot), so the port moves to 8080 — the whole
# reason this image exists. Its own /etc/nginx/nginx.conf already puts the pid
# file and temp paths under /tmp, which is what makes a read-only root
# filesystem possible later; only the server block below is overridden.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
# NUMERIC on purpose. The image defines this user as `nginx`, but kubelet cannot
# verify a *named* user against runAsNonRoot and fails the pod with "has
# non-numeric user (nginx), cannot verify user is non-root". 101 is that user.
USER 101
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
