# ====== STAGE 1: BUILD ======
FROM node:20-alpine AS builder

# Dependências de build e utilitários necessários pelos seus scripts
RUN apk add --no-cache git ffmpeg wget curl bash openssl dos2unix

WORKDIR /evolution

# Copie lockfile junto para cache reprodutível
COPY package*.json tsconfig.json ./
# Instale deps com lock exato (inclui dev deps para build)
RUN npm ci

# Copie o restante do código
COPY src ./src
COPY public ./public
COPY prisma ./prisma
COPY manager ./manager
COPY runWithProvider.js ./
COPY tsup.config.ts ./
COPY Docker ./Docker
# NÃO copie .env para a imagem
# COPY .env.example ./.env   # <- evite

# Normaliza finais de linha para os scripts
RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/*

# Se o seu script gera client do Prisma, etc., mantenha:
RUN ./Docker/scripts/generate_database.sh

# Build do projeto (gera dist/)
RUN npm run build


# ====== STAGE 2: RUNTIME ======
FROM node:20-alpine AS final

RUN apk add --no-cache tzdata ffmpeg bash openssl \
    && addgroup -S nodegrp && adduser -S nodeusr -G nodegrp

ENV TZ=America/Sao_Paulo \
    NODE_ENV=production \
    DOCKER_ENV=true \
    PORT=8080

WORKDIR /evolution

# Copie apenas o necessário
COPY --from=builder /evolution/package*.json ./
# Instale somente prod dependencies
RUN npm ci --omit=dev

# Artefatos de runtime
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

# (Opcional) healthcheck simples—ajuste a rota se existir
# HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
#   CMD wget -qO- http://127.0.0.1:${PORT}/health || exit 1

EXPOSE 8080

# roda como não-root
USER nodeusr

# Executa migrations/ajustes e inicia
ENTRYPOINT ["/bin/bash","-lc",". ./Docker/scripts/deploy_database.sh && npm run start:prod"]
