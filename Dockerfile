FROM node:24-bookworm-slim AS web-builder

WORKDIR /app/web

COPY web/package.json web/package-lock.json ./
RUN npm ci

COPY web ./
RUN npm run build

FROM golang:1.26.2 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=web-builder /app/internal/web/dist ./internal/web/dist

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -o amnezia-panel ./cmd/server

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y ca-certificates docker.io wireguard-tools && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/amnezia-panel .

CMD ["./amnezia-panel"]
