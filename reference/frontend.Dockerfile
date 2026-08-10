# ============================================================
# Reference only. Not runnable from this repository.
#
# In the private source repo this file lives at frontend/Dockerfile
# and is built with the repo root as context:
#
#   build:
#     context: .
#     dockerfile: frontend/Dockerfile
#
# The COPY paths below are relative to that root and are correct for
# it. They are deliberately left unchanged: rewriting them to resolve
# against this documentation repo would break the real build.
#
# Requires `output: "standalone"` in next.config.js for the runner
# stage to find .next/standalone.
# ============================================================

FROM node:20-alpine AS deps
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY frontend/ .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "server.js"]
