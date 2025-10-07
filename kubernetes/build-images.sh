#!/bin/bash

# Build script for job-handler and job-processor Docker images

set -e

# Configuration
REGISTRY="${DOCKER_REGISTRY:-docker.io}"
NAMESPACE="${DOCKER_NAMESPACE:-katson360}"
TAG="${IMAGE_TAG:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Zama Jobs API Docker Images${NC}"
echo "Docker Hub namespace: $NAMESPACE"
echo "Tag: $TAG"
echo ""
echo "Images will be tagged as:"
echo "  - ${NAMESPACE}/zama-job-handler:${TAG}"
echo "  - ${NAMESPACE}/zama-job-processor:${TAG}"
echo ""

# Build job-handler (Rust)
echo -e "${YELLOW}Building job-handler...${NC}"
cd ../examples/job-handler

# Create build context with job-api
rm -rf .dockerbuild 2>/dev/null || true
mkdir -p .dockerbuild

# Copy only necessary files (excluding .dockerbuild itself)
# Use the simpler Dockerfile to avoid cache issues
cp Dockerfile.simple .dockerbuild/Dockerfile
cp Cargo.toml .dockerbuild/
cp Cargo.lock .dockerbuild/ 2>/dev/null || true
cp -r src .dockerbuild/
cp -r ../job-api .dockerbuild/job-api

# Build with proper context and progress
echo "Building Rust application (this may take 5-10 minutes on first build)..."
echo "You will see compilation progress below:"
echo ""
DOCKER_BUILDKIT=1 docker build \
  -t ${NAMESPACE}/zama-job-handler:${TAG} \
  --progress=plain \
  --no-cache \
  .dockerbuild/

# Clean up
rm -rf .dockerbuild
echo -e "${GREEN}✓ job-handler built successfully${NC}"

# Build job-processor (Go)
echo -e "${YELLOW}Building job-processor...${NC}"
cd ../job-processor
echo "Building Go application (this should be quick)..."
DOCKER_BUILDKIT=1 docker build \
  -t ${NAMESPACE}/zama-job-processor:${TAG} \
  --progress=plain \
  .
echo -e "${GREEN}✓ job-processor built successfully${NC}"

# Return to original directory
cd ../../kubernetes

# Push images if requested
if [ "$1" == "push" ]; then
  echo -e "${YELLOW}Pushing images to Docker Hub (${NAMESPACE})...${NC}"

  echo "Pushing job-handler..."
  docker push ${NAMESPACE}/zama-job-handler:${TAG}
  echo -e "${GREEN}✓ job-handler pushed to ${NAMESPACE}/zama-job-handler:${TAG}${NC}"

  echo "Pushing job-processor..."
  docker push ${NAMESPACE}/zama-job-processor:${TAG}
  echo -e "${GREEN}✓ job-processor pushed to ${NAMESPACE}/zama-job-processor:${TAG}${NC}"

  echo ""
  echo -e "${GREEN}Images available at:${NC}"
  echo "  - docker.io/${NAMESPACE}/zama-job-handler:${TAG}"
  echo "  - docker.io/${NAMESPACE}/zama-job-processor:${TAG}"
fi

echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Images built:"
echo "  - ${NAMESPACE}/zama-job-handler:${TAG}"
echo "  - ${NAMESPACE}/zama-job-processor:${TAG}"
echo ""
if [ "$1" != "push" ]; then
  echo "To push images to Docker Hub, run: $0 push"
  echo "Make sure you're logged in: docker login"
fi