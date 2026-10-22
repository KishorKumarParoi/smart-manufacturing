# Multi-stage lightweight Go telemetry gateway container
FROM golang:1.23-alpine AS builder

WORKDIR /usr/src/gateway-go
RUN apk add --no-cache git ca-certificates

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /gateway-go main.go

# Minimal secure runner
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata curl
WORKDIR /app

COPY --from=builder /gateway-go /app/gateway-go

EXPOSE 8080
ENV PORT=8080
USER 1000:1000

CMD ["/app/gateway-go"]
