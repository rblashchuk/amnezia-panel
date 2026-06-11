FROM golang:1.24 AS builder

WORKDIR /app

COPY go.mod .
COPY go.sum .
RUN go mod download

COPY . .

RUN CGO_ENABLED=1 GOOS=linux go build -o vpn-panel ./cmd/server

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y ca-certificates docker.io && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/vpn-panel .

CMD ["./vpn-panel"]