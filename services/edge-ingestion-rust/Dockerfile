# Multi-stage ultra-lightweight Rust edge ingestion container
FROM rust:1.80-alpine AS builder

WORKDIR /usr/src/edge-ingest
RUN apk add --no-cache musl-dev pkgconfig

# Cache dependencies
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

# Build actual binary
COPY src ./src
RUN touch src/main.rs && cargo build --release

# Minimal secure runner
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app

COPY --from=builder /usr/src/edge-ingest/target/release/edge_ingest /app/edge_ingest

EXPOSE 8082
ENV PORT=8082
USER 1000:1000

CMD ["/app/edge_ingest"]
