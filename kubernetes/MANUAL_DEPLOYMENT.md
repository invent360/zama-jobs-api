# Zama Jobs API - Manual Step-by-Step Deployment

This guide provides manual kubectl and helm commands to deploy the Zama Jobs API without using any automation scripts.

## Prerequisites Check

### 1. Verify kubectl is installed and connected
```bash
kubectl version --client
kubectl cluster-info
kubectl get nodes
```

### 2. Verify helm is installed
```bash
helm version
```

### 3. Check cluster resources
```bash
kubectl get storageclass
kubectl get nodes -o wide
```

### 4. Check for node taints (Important for Docker Desktop)
```bash
# Check if nodes have any taints that might prevent pod scheduling
kubectl describe nodes | grep -A 2 "Taints:"

# If you see "node.cilium.io/agent-not-ready:NoSchedule", remove it:
kubectl taint node docker-desktop node.cilium.io/agent-not-ready:NoSchedule- 2>/dev/null || echo "No Cilium taint found"
```

**Important**: If pods get stuck in "Pending" status during deployment, the most common cause is a Cilium taint on the node. Use the fix command above or run `./fix-pending-pods.sh` for automated diagnosis.

---

## Step 1: Create Namespaces

### Create all required namespaces
```bash
kubectl create namespace zama-system
kubectl create namespace kong
kubectl create namespace iam
kubectl create namespace messaging
kubectl create namespace monitoring
kubectl create namespace storage
```

### ✅ Verify Step 1: Check namespaces were created
```bash
# Quick verification - should show all 6 namespaces as "Active"
kubectl get namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)'

# Detailed verification
kubectl get namespaces zama-system kong iam messaging monitoring storage
```

**Expected output**: All 6 namespaces should show as "Active"
**Troubleshoot**: If any namespace is missing, re-run the create command for that namespace

---

## Step 2: Deploy Storage Components

### 2.1 Deploy MinIO Object Storage

#### Create MinIO secret
```bash
kubectl create secret generic minio-secret \
  --from-literal=username=minioadmin \
  --from-literal=password=minioadmin123 \
  -n storage
```

#### Create MinIO StatefulSet and Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: storage
spec:
  serviceName: minio
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:RELEASE.2023-09-04T19-57-37Z
        args:
        - server
        - /data
        - --console-address
        - :9001
        env:
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: username
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: password
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: minio-storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: minio-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: storage
spec:
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
EOF
```

### 2.2 Deploy PostgreSQL Database

#### Create PostgreSQL secret
```bash
kubectl create secret generic postgres-secret \
  --from-literal=username=postgres \
  --from-literal=password=postgres123 \
  -n storage
```

#### Create PostgreSQL ConfigMap
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  namespace: storage
data:
  POSTGRES_DB: zamadb
  POSTGRES_USER: postgres
EOF
```

#### Create PostgreSQL StatefulSet and Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: storage
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        envFrom:
        - configMapRef:
            name: postgres-config
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: storage
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
EOF
```

### 2.3 Deploy Redis Cache

#### Create Redis secret
```bash
kubectl create secret generic redis-secret \
  --from-literal=password=redis123 \
  -n storage
```

#### Create Redis ConfigMap
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: storage
data:
  redis.conf: |
    maxmemory 256mb
    maxmemory-policy allkeys-lru
    save 900 1
    save 300 10
    save 60 10000
EOF
```

#### Create Redis StatefulSet and Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: storage
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        args:
        - redis-server
        - /etc/redis/redis.conf
        - --requirepass
        - $(REDIS_PASSWORD)
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: password
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: redis-config
          mountPath: /etc/redis
        - name: redis-data
          mountPath: /data
      volumes:
      - name: redis-config
        configMap:
          name: redis-config
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: storage
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
EOF
```

### ✅ Verify Step 2: Check storage components deployment
```bash
# Check all storage resources
kubectl get pods,pvc,services -n storage

# Check pod status in detail
kubectl get pods -n storage -o wide

# Check if pods are running (wait if they're in ContainerCreating)
kubectl wait --for=condition=ready pod --all -n storage --timeout=300s

# Check persistent volume claims are bound
kubectl get pvc -n storage

# Test storage connectivity
kubectl exec -it minio-0 -n storage -- mc --version
kubectl exec -it postgres-0 -n storage -- pg_isready -U postgres
kubectl exec -it redis-0 -n storage -- redis-cli ping
```

**Expected**:
- 3 pods running: `minio-0`, `postgres-0`, `redis-0`
- 3 PVCs with status "Bound"
- 3 services available
- All connectivity tests should succeed

**Troubleshoot**:
- If pods are Pending: `kubectl describe pod <pod-name> -n storage`
- If PVCs not bound: `kubectl get storageclass` and `kubectl describe pvc <pvc-name> -n storage`
- If containers failing: `kubectl logs <pod-name> -n storage`

---

## Step 3: Deploy NATS Message Broker

### 3.1 Add NATS Helm Repository
```bash
helm repo add nats https://nats-io.github.io/k8s/helm/charts/
helm repo update
```

### 3.2 Create NATS Values File
```bash
cat <<EOF > nats-values.yaml
# NATS Configuration for Zama Jobs API
# Simplified for Docker Desktop single-node deployment

# Basic configuration
config:
  # Enable JetStream for message persistence
  jetstream:
    enabled: true

  # Enable monitoring
  http_port: 8222

# NATS server settings
nats:
  image:
    repository: nats
    tag: "2.10.12-alpine"
    pullPolicy: IfNotPresent

  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Single replica for Docker Desktop
replicaCount: 1

# Storage settings
persistence:
  enabled: true
  size: 5Gi
  storageClass: hostpath

# Enable box container for debugging
natsBox:
  enabled: true

# Disable cluster mode for single node
cluster:
  enabled: false
  replicas: 1
EOF
```

### 3.3 Install NATS
```bash
# Install NATS with standard release name
NATS_RELEASE_NAME="nats"
echo "Installing NATS with release name: $NATS_RELEASE_NAME"

helm install $NATS_RELEASE_NAME nats/nats \
  --namespace messaging \
  --values nats-values.yaml \
  --timeout 10m \
  --wait
```

### ✅ Verify Step 3: Check NATS message broker deployment
```bash
# Check Helm release status
helm list -n messaging
helm status $NATS_RELEASE_NAME -n messaging

# Check NATS pods and services
kubectl get pods,services -n messaging
kubectl get pods -n messaging -l app.kubernetes.io/name=nats

# Wait for NATS pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nats -n messaging --timeout=300s

# Check NATS logs
kubectl logs -l app.kubernetes.io/name=nats -n messaging --tail=20

# Test NATS connectivity
kubectl port-forward -n messaging svc/nats 4222:4222 &
sleep 5
nc -zv localhost 4222 2>/dev/null && echo "NATS is accessible" || echo "NATS connection failed"
pkill -f "port-forward.*nats"

# Alternative connectivity test using NATS box
kubectl run nats-test --image=natsio/nats-box --rm -i --restart=Never -- \
  nats -s nats://nats.messaging.svc.cluster.local:4222 server info
```

**Expected**:
- Helm release status: "deployed"
- 2 NATS pods running (nats-0 with 2/2 containers ready, and nats-box)
- NATS services available (nats and nats-headless)
- Port 4222 accessible
- Server info shows single-node configuration with JetStream enabled

**Troubleshoot**:
- If Helm install failed: `helm status $NATS_RELEASE_NAME -n messaging`
- If pods not starting: `kubectl describe pod <nats-pod> -n messaging`
- If connectivity fails: `kubectl get svc -n messaging` and check service endpoints
- For startup probe failures with HTTP 503: This is normal during initial startup, wait a few minutes

---

## Step 4: Deploy Keycloak IAM

### 4.1 Create Keycloak Secret
```bash
kubectl create secret generic keycloak-secret \
  --from-literal=admin-username=admin \
  --from-literal=admin-password=admin \
  -n iam
```

### 4.2 Create Keycloak Deployment
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: iam
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:22.0.1
        args:
        - start-dev
        - --import-realm
        env:
        - name: KEYCLOAK_ADMIN
          valueFrom:
            secretKeyRef:
              name: keycloak-secret
              key: admin-username
        - name: KEYCLOAK_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-secret
              key: admin-password
        - name: KC_PROXY
          value: edge
        - name: KC_HOSTNAME_STRICT
          value: "false"
        - name: KC_HTTP_ENABLED
          value: "true"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /realms/master
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /realms/master
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 30
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: iam
spec:
  selector:
    app: keycloak
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

### 4.3 Wait for Keycloak to be Ready
```bash
kubectl wait --for=condition=ready pod -l app=keycloak -n iam --timeout=300s
```

### 4.4 Create Keycloak Realm Configuration
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: zama-realm-config
  namespace: iam
data:
  zama-realm.json: |
    {
      "realm": "zama",
      "enabled": true,
      "displayName": "Zama Jobs API",
      "registrationAllowed": true,
      "loginWithEmailAllowed": true,
      "duplicateEmailsAllowed": false,
      "resetPasswordAllowed": true,
      "editUsernameAllowed": false,
      "bruteForceProtected": true,
      "clients": [
        {
          "clientId": "zama-api",
          "enabled": true,
          "publicClient": false,
          "protocol": "openid-connect",
          "redirectUris": ["*"],
          "webOrigins": ["*"]
        }
      ]
    }
EOF
```

### ✅ Verify Step 4: Check Keycloak IAM deployment
```bash
# Check Keycloak deployment status
kubectl get pods,services,configmaps -n iam
kubectl get deployment keycloak -n iam

# Wait for Keycloak to be ready (this can take 3-5 minutes)
kubectl wait --for=condition=ready pod -l app=keycloak -n iam --timeout=600s

# Check Keycloak pod status and logs
kubectl get pod -l app=keycloak -n iam -o wide
kubectl logs -l app=keycloak -n iam --tail=30

# Test Keycloak web interface
kubectl port-forward -n iam svc/keycloak 8080:8080 &
sleep 10

# Test HTTP response
curl -I http://localhost:8080 2>/dev/null | head -1

# Test Keycloak admin console
curl -s http://localhost:8080/admin/ | grep -q "Keycloak" && echo "Keycloak admin console accessible" || echo "Admin console not ready yet"

# Test master realm
curl -s http://localhost:8080/realms/master | grep -q "realm" && echo "Master realm accessible" || echo "Master realm not ready"

# Stop port forwarding
pkill -f 'port-forward.*keycloak'

# Check realm configuration
kubectl get configmap zama-realm-config -n iam -o yaml
```

**Expected**:
- Keycloak deployment shows 1/1 ready
- Keycloak pod in "Running" status
- HTTP response returns "200 OK"
- Admin console and master realm accessible
- Realm configuration configmap exists

**Troubleshoot**:
- If pod not ready: `kubectl describe pod -l app=keycloak -n iam`
- If startup slow: Keycloak takes 3-5 minutes on first startup
- If connection fails: `kubectl get svc keycloak -n iam` and check endpoints
- Check startup logs: `kubectl logs -l app=keycloak -n iam -f`

**Access Keycloak UI**:
- Run: `kubectl port-forward -n iam svc/keycloak 8080:8080`
- Visit: http://localhost:8080
- Credentials: admin/admin

---

## Step 5: Deploy Kong Gateway

### 5.1 Add Kong Helm Repository
```bash
helm repo add kong https://charts.konghq.com
helm repo update
```

### 5.2 Create Kong Values File
```bash
cat <<EOF > kong-values.yaml
image:
  repository: kong
  tag: "3.4"

env:
  database: "off"
  nginx_worker_processes: "2"
  proxy_access_log: /dev/stdout
  admin_access_log: /dev/stdout
  admin_gui_access_log: /dev/stdout
  portal_api_access_log: /dev/stdout

admin:
  enabled: true
  type: ClusterIP
  http:
    enabled: true
    servicePort: 8001

proxy:
  enabled: true
  type: ClusterIP
  http:
    enabled: true
    servicePort: 80

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false

podDisruptionBudget:
  enabled: false

enterprise:
  enabled: false
EOF
```

### 5.3 Install Kong
```bash
# Install Kong with standard release name
KONG_RELEASE_NAME="kong"
echo "Installing Kong with release name: $KONG_RELEASE_NAME"

helm install $KONG_RELEASE_NAME kong/kong \
  --namespace kong \
  --values kong-values.yaml \
  --timeout 10m \
  --wait
```

### 5.4 Create Kong Plugins Configuration
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kong-plugins
  namespace: kong
data:
  rate-limiting.yaml: |
    _format_version: "3.0"
    plugins:
    - name: rate-limiting
      config:
        minute: 100
        hour: 1000
        policy: local
  oidc.yaml: |
    _format_version: "3.0"
    plugins:
    - name: openid-connect
      config:
        issuer: "http://keycloak.iam.svc.cluster.local:8080/realms/zama"
        client_id: "zama-api"
        client_secret: "your-client-secret"
EOF
```

### ✅ Verify Step 5: Check Kong Gateway deployment
```bash
# Check Kong Helm release status
helm list -n kong
helm status $KONG_RELEASE_NAME -n kong

# Check Kong pods and services
kubectl get pods,services -n kong
kubectl get deployment -l app.kubernetes.io/name=kong -n kong

# Wait for Kong to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kong -n kong --timeout=300s

# Check Kong pod logs
kubectl logs -l app.kubernetes.io/name=kong -n kong --tail=30

# Test Kong Admin API
kubectl port-forward -n kong svc/kong-kong-admin 8001:8001 &
sleep 5

# Check Kong status endpoint
kong_status=$(curl -s http://localhost:8001/status 2>/dev/null)
echo "Kong status response: $kong_status"

# Verify Kong is ready
curl -s http://localhost:8001/status | jq -r '.database.reachable' 2>/dev/null && echo "Kong database reachable" || echo "Kong database check failed"

# Test Kong proxy
kubectl port-forward -n kong svc/kong-kong-proxy 8000:80 &
sleep 3

# Test proxy response (should return Kong's default response)
proxy_response=$(curl -I http://localhost:8000 2>/dev/null | head -1)
echo "Kong proxy response: $proxy_response"

# Stop port forwarding
pkill -f 'port-forward.*kong'

# Check Kong plugins configuration
kubectl get configmap kong-plugins -n kong -o yaml
```

**Expected**:
- Helm release status: "deployed"
- Kong pods in "Running" status
- Admin API returns status JSON with database reachable
- Proxy responds (even if it's a 404, it shows Kong is working)
- Kong plugins configmap exists

**Troubleshoot**:
- If Helm install failed: `helm status $KONG_RELEASE_NAME -n kong`
- If pods not ready: `kubectl describe pod -l app.kubernetes.io/name=kong -n kong`
- If Admin API fails: Check service endpoints with `kubectl get endpoints -n kong`
- Kong startup issues: `kubectl logs -l app.kubernetes.io/name=kong -n kong -f`

**Access Kong Admin API**:
- Run: `kubectl port-forward -n kong svc/kong-kong-admin 8001:8001`
- Visit: http://localhost:8001
- Test: `curl http://localhost:8001/status`

---

## Step 6: Deploy Zama Microservices

### 6.1 Create Job Submission Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: job-submission
  namespace: zama-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: job-submission
  template:
    metadata:
      labels:
        app: job-submission
    spec:
      containers:
      - name: job-submission
        image: zama/job-submission:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          value: "postgresql://postgres:postgres123@postgres.storage.svc.cluster.local:5432/zamadb"
        - name: REDIS_URL
          value: "redis://:redis123@redis.storage.svc.cluster.local:6379"
        - name: NATS_URL
          value: "nats://nats.messaging.svc.cluster.local:4222"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: job-submission
  namespace: zama-system
spec:
  selector:
    app: job-submission
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

### 6.2 Create Job Processing Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: job-processing
  namespace: zama-system
spec:
  replicas: 3
  selector:
    matchLabels:
      app: job-processing
  template:
    metadata:
      labels:
        app: job-processing
    spec:
      containers:
      - name: job-processing
        image: zama/job-processing:latest
        env:
        - name: DATABASE_URL
          value: "postgresql://postgres:postgres123@postgres.storage.svc.cluster.local:5432/zamadb"
        - name: REDIS_URL
          value: "redis://:redis123@redis.storage.svc.cluster.local:6379"
        - name: NATS_URL
          value: "nats://nats.messaging.svc.cluster.local:4222"
        - name: MINIO_URL
          value: "minio.storage.svc.cluster.local:9000"
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: job-processing
  namespace: zama-system
spec:
  selector:
    app: job-processing
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

### 6.3 Create Blockchain Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blockchain-service
  namespace: zama-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockchain-service
  template:
    metadata:
      labels:
        app: blockchain-service
    spec:
      containers:
      - name: blockchain-service
        image: zama/blockchain-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          value: "postgresql://postgres:postgres123@postgres.storage.svc.cluster.local:5432/zamadb"
        - name: NATS_URL
          value: "nats://nats.messaging.svc.cluster.local:4222"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: blockchain-service
  namespace: zama-system
spec:
  selector:
    app: blockchain-service
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

### 6.4 Create Metering Service
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metering-service
  namespace: zama-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metering-service
  template:
    metadata:
      labels:
        app: metering-service
    spec:
      containers:
      - name: metering-service
        image: zama/metering-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          value: "postgresql://postgres:postgres123@postgres.storage.svc.cluster.local:5432/zamadb"
        - name: REDIS_URL
          value: "redis://:redis123@redis.storage.svc.cluster.local:6379"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: metering-service
  namespace: zama-system
spec:
  selector:
    app: metering-service
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

### ✅ Verify Step 6: Check Zama microservices deployment
```bash
# Check all Zama deployments and pods
kubectl get deployments,pods,services -n zama-system
kubectl get pods -n zama-system -o wide

# Check deployment status in detail
kubectl get deployment job-submission -n zama-system
kubectl get deployment job-processing -n zama-system
kubectl get deployment blockchain-service -n zama-system
kubectl get deployment metering-service -n zama-system

# Wait for all deployments to be ready
kubectl wait --for=condition=available deployment --all -n zama-system --timeout=300s

# Check replica sets
kubectl get replicasets -n zama-system

# Check pod logs for each service
echo "=== Job Submission Service Logs ==="
kubectl logs -l app=job-submission -n zama-system --tail=10

echo "=== Job Processing Service Logs ==="
kubectl logs -l app=job-processing -n zama-system --tail=10

echo "=== Blockchain Service Logs ==="
kubectl logs -l app=blockchain-service -n zama-system --tail=10

echo "=== Metering Service Logs ==="
kubectl logs -l app=metering-service -n zama-system --tail=10

# Check service endpoints
kubectl get endpoints -n zama-system

# Check recent events
kubectl get events -n zama-system --sort-by=.metadata.creationTimestamp --field-selector type!=Normal

# Test service connectivity (internal cluster DNS)
kubectl run test-services --image=busybox --rm -i --restart=Never -- \
  nslookup job-submission.zama-system.svc.cluster.local

# Check if services are responding (basic connectivity)
kubectl run test-http --image=curlimages/curl --rm -i --restart=Never -- \
  curl -I http://job-submission.zama-system.svc.cluster.local:8080 --max-time 10
```

**Expected**:
- 4 deployments: job-submission (2/2), job-processing (3/3), blockchain-service (1/1), metering-service (1/1)
- All pods in "Running" status
- All deployments show "AVAILABLE"
- Services have endpoints
- DNS resolution works for services
- No error events

**Troubleshoot**:
- If deployments not ready: `kubectl describe deployment <deployment-name> -n zama-system`
- If pods failing: `kubectl describe pod <pod-name> -n zama-system`
- If image pull errors: Check if images exist or are accessible
- If connectivity fails: `kubectl get svc -n zama-system` and check ClusterIP
- Check resource constraints: `kubectl top pods -n zama-system`

---

## Step 7: Apply Network Policies

### 7.1 Create Network Policy for Storage Namespace
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: storage-network-policy
  namespace: storage
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: zama-system
    - namespaceSelector:
        matchLabels:
          name: messaging
  - from: []
    ports:
    - protocol: TCP
      port: 5432
    - protocol: TCP
      port: 6379
    - protocol: TCP
      port: 9000
EOF
```

### 7.2 Create Network Policy for Messaging Namespace
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: messaging-network-policy
  namespace: messaging
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: zama-system
    - namespaceSelector:
        matchLabels:
          name: kong
  - from: []
    ports:
    - protocol: TCP
      port: 4222
    - protocol: TCP
      port: 6222
    - protocol: TCP
      port: 8222
EOF
```

### 7.3 Create Network Policy for IAM Namespace
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: iam-network-policy
  namespace: iam
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kong
    - namespaceSelector:
        matchLabels:
          name: zama-system
  - from: []
    ports:
    - protocol: TCP
      port: 8080
EOF
```

### ✅ Verify Step 7: Check network policies deployment
```bash
# Check all network policies
kubectl get networkpolicies --all-namespaces
kubectl get networkpolicy -n storage
kubectl get networkpolicy -n messaging
kubectl get networkpolicy -n iam

# Describe network policies in detail
echo "=== Storage Network Policy ==="
kubectl describe networkpolicy storage-network-policy -n storage

echo "=== Messaging Network Policy ==="
kubectl describe networkpolicy messaging-network-policy -n messaging

echo "=== IAM Network Policy ==="
kubectl describe networkpolicy iam-network-policy -n iam

# Test network connectivity between namespaces (should be restricted)
# Test from zama-system to storage (should work)
kubectl run connectivity-test-1 --image=busybox --rm -i --restart=Never -n zama-system -- \
  nc -zv postgres.storage.svc.cluster.local 5432 -w 5

# Test from default namespace to storage (should be blocked)
kubectl run connectivity-test-2 --image=busybox --rm -i --restart=Never -- \
  nc -zv postgres.storage.svc.cluster.local 5432 -w 5

# Check that DNS still works (basic connectivity)
kubectl run dns-test --image=busybox --rm -i --restart=Never -n zama-system -- \
  nslookup postgres.storage.svc.cluster.local

# Verify policies are correctly applied
kubectl get pods --show-labels -n storage
kubectl get pods --show-labels -n messaging
kubectl get pods --show-labels -n iam
```

**Expected**:
- 3 network policies created: storage-network-policy, messaging-network-policy, iam-network-policy
- Policies show correct ingress rules
- Connectivity from zama-system to storage works
- Connectivity from default namespace to storage is blocked
- DNS resolution still works

**Troubleshoot**:
- If policies not created: Re-run the kubectl apply commands
- If connectivity not working as expected: Check policy selectors and namespaceSelector labels
- CNI compatibility: Some CNIs don't support NetworkPolicies (check with `kubectl get crd networkpolicies.networking.k8s.io`)

**Note**: Network policies only work if your CNI supports them. Docker Desktop's default CNI may not enforce network policies.

---

## Step 8: Deploy Monitoring Stack

### 8.1 Create Prometheus
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.45.0
        ports:
        - containerPort: 9090
        args:
        - "--config.file=/etc/prometheus/prometheus.yml"
        - "--storage.tsdb.path=/prometheus/"
        - "--web.console.libraries=/etc/prometheus/console_libraries"
        - "--web.console.templates=/etc/prometheus/consoles"
        - "--web.enable-lifecycle"
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus
        - name: prometheus-storage
          mountPath: /prometheus
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: prometheus-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
EOF
```

### 8.2 Create Grafana
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.0.0
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: admin
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: admin
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      volumes:
      - name: grafana-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
EOF
```

### ✅ Verify Step 8: Check monitoring stack deployment
```bash
# Check monitoring deployments and pods
kubectl get deployments,pods,services -n monitoring
kubectl get pods -n monitoring -o wide

# Wait for monitoring pods to be ready
kubectl wait --for=condition=ready pod --all -n monitoring --timeout=300s

# Check Prometheus deployment
kubectl get deployment prometheus -n monitoring
kubectl logs -l app=prometheus -n monitoring --tail=20

# Check Grafana deployment
kubectl get deployment grafana -n monitoring
kubectl logs -l app=grafana -n monitoring --tail=20

# Test Prometheus access
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
sleep 5

# Check Prometheus health
prometheus_health=$(curl -s http://localhost:9090/-/healthy 2>/dev/null)
echo "Prometheus health: $prometheus_health"

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets | length' 2>/dev/null && echo "Prometheus targets loaded" || echo "Prometheus API not ready"

# Test Grafana access
kubectl port-forward -n monitoring svc/grafana 3000:3000 &
sleep 5

# Check Grafana health
grafana_health=$(curl -s http://localhost:3000/api/health 2>/dev/null)
echo "Grafana health: $grafana_health"

# Stop port forwarding
pkill -f 'port-forward.*prometheus'
pkill -f 'port-forward.*grafana'

# Check ConfigMaps
kubectl get configmap prometheus-config -n monitoring -o yaml | head -20
```

**Expected**:
- Prometheus and Grafana deployments show 1/1 ready
- All pods in "Running" status
- Prometheus health returns "Prometheus is Healthy."
- Grafana health returns status information
- ConfigMaps exist for configuration

**Troubleshoot**:
- If pods not ready: `kubectl describe pod <pod-name> -n monitoring`
- If Prometheus not healthy: Check logs and configuration
- If Grafana not accessible: Verify service and pod status
- Resource issues: `kubectl top pods -n monitoring`

**Access Monitoring**:
- Prometheus: `kubectl port-forward -n monitoring svc/prometheus 9090:9090` → http://localhost:9090
- Grafana: `kubectl port-forward -n monitoring svc/grafana 3000:3000` → http://localhost:3000 (admin/admin)

---

## Final Verification

## ✅ Final Verification: Complete System Check

### Comprehensive Status Check
```bash
echo "=========================================="
echo "ZAMA JOBS API - FINAL VERIFICATION"
echo "=========================================="

# 1. Check all namespaces exist
echo "=== NAMESPACES ==="
kubectl get namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | wc -l
kubectl get namespaces zama-system kong iam messaging monitoring storage

# 2. Check all pods are running
echo "=== PODS STATUS ==="
kubectl get pods --all-namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)'

# Count running vs total pods
total_pods=$(kubectl get pods --all-namespaces --no-headers | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | wc -l)
running_pods=$(kubectl get pods --all-namespaces --no-headers | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | grep -c 'Running')
echo "Running pods: $running_pods/$total_pods"

# 3. Check all PVCs are bound
echo "=== PERSISTENT VOLUMES ==="
kubectl get pvc --all-namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)'
unbound_pvcs=$(kubectl get pvc --all-namespaces --no-headers | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | grep -v 'Bound' | wc -l)
echo "Unbound PVCs: $unbound_pvcs"

# 4. Check all services have endpoints
echo "=== SERVICES AND ENDPOINTS ==="
kubectl get services --all-namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)'
kubectl get endpoints --all-namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | grep '<none>' || echo "All services have endpoints"

# 5. Check Helm releases
echo "=== HELM RELEASES ==="
helm list --all-namespaces

# 6. Check for any warning events
echo "=== WARNING EVENTS ==="
kubectl get events --all-namespaces --field-selector type=Warning | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | tail -10

# 7. Check node status
echo "=== NODE STATUS ==="
kubectl get nodes -o wide
kubectl describe nodes | grep -A 2 "Taints:" | grep -v "^$"

# 8. Resource usage
echo "=== RESOURCE USAGE ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
kubectl top pods --all-namespaces 2>/dev/null | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' || echo "Pod metrics not available"
```

### System Health Summary
```bash
echo "=========================================="
echo "HEALTH SUMMARY"
echo "=========================================="

# Create health report
cat << 'EOF' > /tmp/health-check.sh
#!/bin/bash

# Count healthy components
healthy=0
total=8

echo "Component Health Check:"

# 1. Namespaces
if [ $(kubectl get namespaces | grep -E '(zama-system|kong|iam|messaging|monitoring|storage)' | wc -l) -eq 6 ]; then
  echo "✅ Namespaces: 6/6 exist"
  ((healthy++))
else
  echo "❌ Namespaces: Missing namespaces"
fi

# 2. Storage
storage_running=$(kubectl get pods -n storage --no-headers | grep -c 'Running')
if [ $storage_running -eq 3 ]; then
  echo "✅ Storage: All pods running ($storage_running/3)"
  ((healthy++))
else
  echo "❌ Storage: Only $storage_running/3 pods running"
fi

# 3. Messaging (NATS)
nats_running=$(kubectl get pods -n messaging --no-headers | grep -c 'Running')
if [ $nats_running -ge 2 ]; then
  echo "✅ Messaging: NATS single-node running ($nats_running pods)"
  ((healthy++))
else
  echo "❌ Messaging: NATS not fully running ($nats_running pods expected: 2)"
fi

# 4. IAM (Keycloak)
iam_running=$(kubectl get pods -n iam --no-headers | grep -c 'Running')
if [ $iam_running -ge 1 ]; then
  echo "✅ IAM: Keycloak running"
  ((healthy++))
else
  echo "❌ IAM: Keycloak not running"
fi

# 5. Gateway (Kong)
kong_running=$(kubectl get pods -n kong --no-headers | grep -c 'Running')
if [ $kong_running -ge 1 ]; then
  echo "✅ Gateway: Kong running"
  ((healthy++))
else
  echo "❌ Gateway: Kong not running"
fi

# 6. Microservices
zama_running=$(kubectl get pods -n zama-system --no-headers | grep -c 'Running')
if [ $zama_running -ge 4 ]; then
  echo "✅ Microservices: All services running ($zama_running pods)"
  ((healthy++))
else
  echo "❌ Microservices: Only $zama_running pods running"
fi

# 7. Monitoring
monitoring_running=$(kubectl get pods -n monitoring --no-headers | grep -c 'Running')
if [ $monitoring_running -ge 2 ]; then
  echo "✅ Monitoring: Prometheus and Grafana running"
  ((healthy++))
else
  echo "❌ Monitoring: Only $monitoring_running/2 pods running"
fi

# 8. Network Policies
policies_count=$(kubectl get networkpolicies --all-namespaces --no-headers | wc -l)
if [ $policies_count -ge 3 ]; then
  echo "✅ Network Policies: $policies_count policies applied"
  ((healthy++))
else
  echo "❌ Network Policies: Only $policies_count policies found"
fi

echo ""
echo "Overall Health: $healthy/$total components healthy"

if [ $healthy -eq $total ]; then
  echo "🎉 DEPLOYMENT SUCCESSFUL! All components are healthy."
  exit 0
elif [ $healthy -ge 6 ]; then
  echo "⚠️  DEPLOYMENT MOSTLY SUCCESSFUL with minor issues."
  exit 1
else
  echo "❌ DEPLOYMENT HAS ISSUES. Check failed components."
  exit 2
fi
EOF

chmod +x /tmp/health-check.sh
/tmp/health-check.sh
rm /tmp/health-check.sh
```

### Test Connectivity Between Services
```bash
# Test database connection from a pod
kubectl run test-db --image=postgres:15-alpine --rm -it -- psql -h postgres.storage.svc.cluster.local -U postgres -d zamadb

# Test Redis connection
kubectl run test-redis --image=redis:7-alpine --rm -it -- redis-cli -h redis.storage.svc.cluster.local -a redis123 ping

# Test NATS connection
kubectl run test-nats --image=natsio/nats-box --rm -it -- nats -s nats://nats.messaging.svc.cluster.local:4222 server info
```

### Access Web Interfaces
```bash
# Keycloak (admin/admin)
kubectl port-forward -n iam svc/keycloak 8080:8080

# Kong Admin API
kubectl port-forward -n kong svc/kong-kong-admin 8001:8001

# Kong Gateway
kubectl port-forward -n kong svc/kong-kong-proxy 8000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Grafana (admin/admin)
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

---

## Troubleshooting

### Common Issues and Solutions

#### Pods Stuck in Pending
```bash
# Check node resources
kubectl describe nodes

# Check events
kubectl get events --all-namespaces --field-selector type=Warning

# Check pod details
kubectl describe pod <pod-name> -n <namespace>
```

#### PVC Not Binding
```bash
# Check storage classes
kubectl get storageclass

# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>
```

#### Service Not Accessible
```bash
# Check service endpoints
kubectl get endpoints -n <namespace>

# Check service details
kubectl describe service <service-name> -n <namespace>
```

#### Container Crashes
```bash
# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check resource usage
kubectl top pods -n <namespace>
```

---

## Cleanup (Optional)

To remove the entire deployment:

```bash
# Delete all resources by namespace
kubectl delete namespace zama-system kong iam messaging monitoring storage

# Uninstall Helm releases
helm uninstall $NATS_RELEASE_NAME -n messaging
helm uninstall $KONG_RELEASE_NAME -n kong

# Remove temporary files
rm -f nats-values.yaml kong-values.yaml
```

---

This manual deployment process gives you complete control over each step and allows you to understand exactly what is being deployed in your Kubernetes cluster.