# ---- build stage ----
# Full dependency tree lives here: the prisma CLI, @prisma/engines and tsc are
# all devDependencies. Pruning is deliberately NOT done in this stage — the
# migrate stage needs the un-pruned tree.
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npm run build

# ---- migration image ----
# Built explicitly with `--target migrate`; BuildKit skips it otherwise.
# `prisma migrate deploy` has NO --url flag in v7 — the datasource comes from
# prisma.config.ts, so that file and prisma/ both have to be here alongside the
# un-pruned node_modules that still contains the CLI.
FROM node:24-alpine AS migrate
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/prisma.config.ts ./prisma.config.ts
USER node
CMD ["node", "node_modules/prisma/build/index.js", "migrate", "deploy"]

# ---- prune devDeps for the runtime image ----
FROM build AS prune
RUN npm prune --omit=dev

# ---- runtime stage ----
# MUST stay the last stage: compose's `build: ./backend` and cd.yml both build
# with no --target, which resolves to the final stage.
FROM node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=prune /app/node_modules ./node_modules
COPY --from=prune /app/dist ./dist
COPY package.json ./
# the node image ships a non-root 'node' user — drop root
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
