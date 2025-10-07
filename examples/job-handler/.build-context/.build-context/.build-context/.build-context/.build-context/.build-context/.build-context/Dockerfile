# Build stage
FROM rust:1.75-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev protoc protobuf-dev

# Create app directory
WORKDIR /build

# Copy the job-api for shared dependencies (will be provided in build context)
COPY job-api /job-api

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Copy source code
COPY src ./src

# Build the application in release mode
RUN cargo build --release --bin job-handler

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates libgcc

# Create non-root user
RUN addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/target/release/job-handler .

# Change ownership
RUN chown -R appuser:appuser /app

# Use non-root user
USER appuser

# Expose gRPC port
EXPOSE 50051

# Expose WebSocket port (if used)
EXPOSE 8080

# Set environment variable defaults
ENV NATS_URL=nats://nats-service:4222
ENV RUST_LOG=info

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["sh", "-c", "nc -z localhost 50051 || exit 1"]

# Run the application
ENTRYPOINT ["./job-handler"]