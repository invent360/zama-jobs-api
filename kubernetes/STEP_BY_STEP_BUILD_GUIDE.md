# Step-by-Step Guide: Build and Push Docker Images

## Prerequisites
- Docker installed and running
- Docker Hub account (username: katson360)
- Terminal/command line access

## Step 1: Clean Up Any Previous Issues

```bash
# Navigate to the kubernetes directory
cd /Users/admin/Dev-o/zama-jobs-api/kubernetes

# Clean up any leftover build directories
cd ../examples/job-handler
rm -rf .dockerbuild
cd ../../kubernetes

# Clean Docker cache if needed (optional)
docker system prune -f
```

## Step 2: Login to Docker Hub

```bash
# Login to Docker Hub
docker login

# Enter your Docker Hub credentials:
# Username: katson360
# Password: [your password]
```

## Step 3: Build Job-Processor First (Go - Fast Build)

This is quick and lets you verify the process works:

```bash
# Navigate to job-processor directory
cd ../examples/job-processor

# Build the Go image (takes ~30 seconds)
docker build -t katson360/zama-job-processor:latest .

# Verify it was created
docker images | grep zama-job-processor
```

## Step 4: Build Job-Handler (Rust - Slow Build)

### Option A: Manual Build (Recommended for first time)

```bash
# Navigate to job-handler directory
cd ../job-handler

# Create a clean build directory
rm -rf build-temp 2>/dev/null
mkdir build-temp

# Copy necessary files
cp Dockerfile build-temp/
cp Cargo.toml build-temp/
cp Cargo.lock build-temp/ 2>/dev/null || true
cp -r src build-temp/
cp -r ../job-api build-temp/job-api

# Build the image (5-10 minutes)
cd build-temp
docker build -t katson360/zama-job-handler:latest .

# Clean up
cd ..
rm -rf build-temp
```

### Option B: Use the Fixed Script

```bash
# Go back to kubernetes directory
cd ../../kubernetes

# Run the build script
./build-images.sh
```

## Step 5: Verify Images Were Built

```bash
# List your images
docker images | grep katson360

# You should see:
# katson360/zama-job-handler      latest    xxxxxxxxxxxx   X minutes ago    50MB
# katson360/zama-job-processor    latest    xxxxxxxxxxxx   X minutes ago    20MB
```

## Step 6: Push Images to Docker Hub

```bash
# Push job-processor (fast)
docker push katson360/zama-job-processor:latest

# Push job-handler (may take a minute)
docker push katson360/zama-job-handler:latest
```

## Step 7: Verify on Docker Hub

Visit: https://hub.docker.com/u/katson360
You should see both images:
- katson360/zama-job-handler
- katson360/zama-job-processor

## Alternative: Complete Script

If you want to do everything at once:

```bash
cd /Users/admin/Dev-o/zama-jobs-api/kubernetes

# Clean, build, and push
./build-images.sh push
```

## Troubleshooting

### If build is stuck:
- Press `Ctrl+C` to cancel
- Check Docker daemon: `docker ps -a`
- Clean up: `docker system prune -af`

### If "name too long" errors:
- Make sure no `.dockerbuild` exists in job-handler
- Use manual build method (Step 4, Option A)

### To see build progress:
```bash
# In another terminal while building:
docker ps  # See running containers
docker logs -f [CONTAINER_ID]  # Follow build logs
```

### If push fails:
```bash
# Re-login
docker logout
docker login

# Try push again
docker push katson360/zama-job-handler:latest
```

## Quick Commands Summary

```bash
# Complete build and push
cd /Users/admin/Dev-o/zama-jobs-api/kubernetes
docker login
./build-images.sh push

# Just build locally
./build-images.sh

# Build only Go service (fast test)
cd ../examples/job-processor
docker build -t katson360/zama-job-processor:latest .

# Clean everything and start over
docker system prune -af
rm -rf ../examples/*/.dockerbuild
```

## Expected Build Times

- **job-processor (Go)**: 30-60 seconds
- **job-handler (Rust)**:
  - First build: 5-10 minutes
  - Subsequent builds (with cache): 1-2 minutes

## Success Indicators

✅ No error messages
✅ Images appear in `docker images`
✅ Push completes without errors
✅ Images visible on Docker Hub

## Next Steps

Once images are on Docker Hub, deploy to Kubernetes:

```bash
# Deploy to development environment
kubectl apply -k overlays/development/

# Check deployment
kubectl get pods -n zama-jobs-dev
```