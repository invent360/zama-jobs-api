# Job Processor (Go)

A Go-based job processor that subscribes to NATS messages, processes jobs asynchronously, and publishes completion events.

## Features

- NATS message queue integration
- Asynchronous job processing
- Configurable success rate (default: 90%)
- Simulated processing time (1-6 seconds)
- Structured logging with Logrus
- Graceful shutdown handling

## Prerequisites

- Go 1.21 or later
- NATS server running (default: localhost:4222)

## Installation

```bash
# Download dependencies
go mod download

# Build the binary
make build

# Or use go build directly
go build -o job-processor .
```

## Running

```bash
# Using make
make run

# Using the built binary
./job-processor

# With custom NATS URL
NATS_URL=nats://your-nats-server:4222 ./job-processor
```

## Configuration

The processor can be configured through environment variables:

- `NATS_URL`: NATS server URL (default: "nats://localhost:4222")

## Project Structure

```
job-processor/
├── main.go                 # Main entry point
├── model/                  # Data models
│   ├── job_status.go      # Job status enum
│   ├── job_event.go       # Job event structure
│   └── job_completion_event.go # Completion event structure
├── logic/                  # Business logic
│   └── processor.go       # Job processor implementation
├── go.mod                 # Go module definition
├── Makefile              # Build commands
└── README.md             # This file
```

## Message Format

### Job Event (Subscribe to `jobs.submit`)
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "Pending",
  "payload": "Job data",
  "timestamp": 1704067200
}
```

### Job Completion Event (Publish to `jobs.complete`)
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "Completed",
  "result": "Job processed successfully in 2500ms",
  "completed_at": 1704067203
}
```

## Development

```bash
# Run tests
make test

# Clean build artifacts
make clean

# Build for multiple platforms
make build-all
```