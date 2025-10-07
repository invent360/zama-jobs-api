# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

# Set working directory
WORKDIR /build

# Copy go mod files
COPY go.mod ./

# Download dependencies and create go.sum
RUN go mod download && go mod tidy

# Copy source code
COPY . .

# Build the application with optimizations
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -a -installsuffix cgo -o job-processor .

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/job-processor .

# Change ownership
RUN chown -R appuser:appuser /app

# Use non-root user
USER appuser

# Set environment variable defaults
ENV NATS_URL=nats://nats-service:4222

# Health check (optional - checks if process is running)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["sh", "-c", "ps aux | grep job-processor | grep -v grep || exit 1"]

# Run the application
ENTRYPOINT ["./job-processor"]