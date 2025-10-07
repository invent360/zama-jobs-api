.PHONY: build run clean deps test

# Build the job-processor binary
build:
	go build -o job-processor .

# Run the job-processor
run:
	go run .

# Clean build artifacts
clean:
	rm -f job-processor

# Download dependencies
deps:
	go mod download
	go mod tidy

# Run tests
test:
	go test ./...

# Build for multiple platforms
build-all:
	GOOS=linux GOARCH=amd64 go build -o job-processor-linux-amd64 .
	GOOS=darwin GOARCH=amd64 go build -o job-processor-darwin-amd64 .
	GOOS=darwin GOARCH=arm64 go build -o job-processor-darwin-arm64 .
	GOOS=windows GOARCH=amd64 go build -o job-processor-windows-amd64.exe .