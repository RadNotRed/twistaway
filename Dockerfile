# syntax=docker/dockerfile:1

FROM oven/bun:1.3.14-debian AS build

WORKDIR /app

COPY package.json bun.lock ./
COPY apps/api/package.json apps/api/package.json
COPY apps/site/package.json apps/site/package.json
COPY packages/shared/package.json packages/shared/package.json

RUN bun install --frozen-lockfile

COPY apps/api/src apps/api/src
COPY apps/api/tsconfig.json apps/api/tsconfig.json
COPY packages/shared/src packages/shared/src
COPY packages/shared/tsconfig.json packages/shared/tsconfig.json

RUN bun run --filter @twistaway/shared build \
    && bun run --filter @twistaway/api build \
    && rm -rf node_modules apps/api/node_modules apps/site/node_modules packages/shared/node_modules \
    && bun install --frozen-lockfile --production --filter @twistaway/api

FROM node:25-bookworm-slim AS runtime

ENV NODE_ENV=production \
    PORT=4180 \
    DB_PATH=/data/twistaway.sqlite

WORKDIR /app

COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/apps/api/node_modules ./apps/api/node_modules
COPY --from=build --chown=node:node /app/apps/api/dist ./apps/api/dist
COPY --from=build --chown=node:node /app/apps/api/package.json ./apps/api/package.json
COPY --from=build --chown=node:node /app/packages/shared/dist ./packages/shared/dist
COPY --from=build --chown=node:node /app/packages/shared/package.json ./packages/shared/package.json

RUN mkdir -p /data && chown node:node /data

USER node

EXPOSE 4180
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:4180/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]

CMD ["node", "apps/api/dist/server.js"]
