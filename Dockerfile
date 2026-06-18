FROM golang:1.26.2 AS collector-builder

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH:-$(go env GOARCH)}" \
    go build -trimpath -ldflags="-s -w" -o amnezia-panel ./cmd/server

FROM scratch AS collector

WORKDIR /app

COPY --from=collector-builder /app/amnezia-panel /amnezia-panel

CMD ["/amnezia-panel"]

FROM node:24-bookworm-slim AS web-builder

WORKDIR /app/web

COPY web/package.json web/package-lock.json ./
RUN npm ci

COPY web ./
RUN npm run build

FROM golang:1.26.2 AS panel-builder

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=web-builder /app/internal/web/dist ./internal/web/dist

RUN CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH:-$(go env GOARCH)}" \
    go build -trimpath -ldflags="-s -w" -o amnezia-panel ./cmd/server

FROM debian:bookworm-slim AS panel

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=panel-builder /app/amnezia-panel /amnezia-panel

CMD ["/amnezia-panel"]
