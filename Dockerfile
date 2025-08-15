# ====== STAGE 1: BUILD ======
FROM node:20-alpine AS builder

# Dependências de build e utilitários necessários pelos seus scripts
RUN apk add --no-cache git ffmpeg wget curl bash openssl dos2unix

WORKDIR /evolution

# Copie lockfile junto para cache reprodutível
COPY package*.json tsconfig.json ./
RUN npm ci

# Copie o restante do código
COPY src ./src
COPY public ./public
COPY prisma ./prisma
COPY manager ./manager
COPY runWithProvider.js ./
COPY tsup.config.ts ./
COPY Docker ./Docker

# Copia o example para usar temporariamente no build
COPY .env.example ./.env.example

# Scripts: normaliza finais de linha, cria .env temporário, roda o generate e remove o .env
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

# Copie apenas o necessário e instale somente prod
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

EXPOSE 8080
USER nodeusr

ENTRYPOINT ["/bin/bash","-lc",". ./Docker/scripts/deploy_database.sh && npm run start:prod"]
