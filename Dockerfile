# ====== STAGE 1: BUILD ======
FROM node:20-alpine AS builder

# Dependências para build e scripts
RUN apk add --no-cache git ffmpeg wget curl bash openssl dos2unix

WORKDIR /evolution

# Instala dependências com lockfile (cache eficiente e reprodutível)
COPY package*.json tsconfig.json ./
RUN npm ci

# Copia código e assets
COPY src ./src
COPY public ./public
COPY prisma ./prisma
COPY manager ./manager
COPY runWithProvider.js ./
COPY tsup.config.ts ./
COPY Docker ./Docker
COPY .env.example ./.env.example

# Normaliza scripts + usa .env.example apenas para o build (gera client/migrations, etc.)
RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/* && \
    cp -f .env.example .env && \
    ./Docker/scripts/generate_database.sh && \
    rm -f .env

# Compila (gera dist/)
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

# package + deps (somente prod)
COPY --from=builder /evolution/package*.json ./
RUN npm ci --omit=dev

# Artefatos de runtime
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

# >>> Garantir permissões para o usuário não-root
RUN chown -R nodeusr:nodegrp /evolution

EXPOSE 8080
USER nodeusr

# Fallback: se DATABASE_URL não vier, usa DATABASE_CONNECTION_URI
ENTRYPOINT ["/bin/bash","-lc","export DATABASE_URL=${DATABASE_URL:-$DATABASE_CONNECTION_URI}; . ./Docker/scripts/deploy_database.sh && npm run start:prod"]
