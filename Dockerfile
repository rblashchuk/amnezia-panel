FROM golang:1.24 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -o vpn-panel ./cmd/server

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y ca-certificates docker-cli && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/vpn-panel .

CMD ["./vpn-panel"]