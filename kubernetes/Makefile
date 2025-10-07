# Zama Jobs API - Kubernetes Makefile
# Alternative to deploy.sh with better dependency management

.PHONY: help all deploy clean check-deps install-deps \
        deploy-namespaces deploy-cilium deploy-storage deploy-nats \
        deploy-keycloak deploy-kong deploy-services deploy-policies \
        deploy-monitoring port-forward test status logs \
        scale-up scale-down restart-services update-images

# Default target
.DEFAULT_GOAL := help

# Configuration
CLUSTER_TYPE ?= $(shell kubectl config current-context | grep -q "minikube" && echo "minikube" || echo "docker-desktop")
CILIUM_VERSION ?= 1.18.2
KONG_VERSION ?= 3.4
KEYCLOAK_VERSION ?= 22.0.1
NATS_VERSION ?= 2.10.0

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
MAGENTA := \033[35m
CYAN := \033[36m
WHITE := \033[37m
RESET := \033[0m

# Help target
help: ## Show this help message
	@echo "$(CYAN)Zama Jobs API - Kubernetes Deployment$(RESET)"
	@echo "$(YELLOW)Usage: make [target]$(RESET)"
	@echo ""
	@echo "$(GREEN)Main Targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Configuration:$(RESET)"
	@echo "  CLUSTER_TYPE: $(CLUSTER_TYPE)"
	@echo "  CILIUM_VERSION: $(CILIUM_VERSION)"
	@echo "  KONG_VERSION: $(KONG_VERSION)"
	@echo "  KEYCLOAK_VERSION: $(KEYCLOAK_VERSION)"
	@echo "  NATS_VERSION: $(NATS_VERSION)"

# Dependency checks
check-deps: ## Check if required tools are installed
	@echo "$(YELLOW)Checking dependencies...$(RESET)"
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)Error: kubectl is not installed$(RESET)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)Error: helm is not installed$(RESET)"; exit 1; }
	@kubectl cluster-info >/dev/null 2>&1 || { echo "$(RED)Error: Cannot connect to Kubernetes cluster$(RESET)"; exit 1; }
	@echo "$(GREEN)✓ All dependencies are available$(RESET)"

install-deps: ## Install missing dependencies
	@echo "$(YELLOW)Installing dependencies...$(RESET)"
ifeq ($(shell uname -s),Darwin)
	@command -v kubectl >/dev/null 2>&1 || brew install kubectl
	@command -v helm >/dev/null 2>&1 || brew install helm
else
	@echo "$(YELLOW)Please install kubectl and helm manually on Linux$(RESET)"
endif

# Status checks
cluster-info: check-deps ## Show cluster information
	@echo "$(CYAN)Kubernetes Cluster Information:$(RESET)"
	@kubectl cluster-info
	@echo ""
	@echo "$(CYAN)Cluster Context:$(RESET)"
	@kubectl config current-context
	@echo ""
	@echo "$(CYAN)Available Nodes:$(RESET)"
	@kubectl get nodes

status: ## Show deployment status
	@echo "$(CYAN)Deployment Status:$(RESET)"
	@echo ""
	@echo "$(YELLOW)Namespaces:$(RESET)"
	@kubectl get namespaces | grep -E "(zama|kong|iam|messaging|monitoring|storage)" || echo "No Zama namespaces found"
	@echo ""
	@echo "$(YELLOW)Pods Status:$(RESET)"
	@kubectl get pods --all-namespaces | grep -E "(zama|kong|keycloak|nats|postgres|redis|minio|cilium)" || echo "No Zama pods found"
	@echo ""
	@echo "$(YELLOW)Services:$(RESET)"
	@kubectl get services --all-namespaces | grep -E "(zama|kong|keycloak|nats|postgres|redis|minio)" || echo "No Zama services found"

# Main deployment targets
all: deploy ## Deploy the complete stack (alias for deploy)

deploy: check-deps deploy-namespaces deploy-storage deploy-cilium deploy-nats deploy-keycloak deploy-kong deploy-services deploy-policies deploy-monitoring ## Deploy the complete Zama Jobs API stack
	@echo "$(GREEN)========================================"
	@echo "Deployment Complete!"
	@echo "========================================$(RESET)"
	@echo ""
	@echo "$(CYAN)Next steps:$(RESET)"
	@echo "  1. Run 'make port-forward' to access services"
	@echo "  2. Run 'make test' to verify deployment"
	@echo ""
	@echo "$(CYAN)Service URLs (after port forwarding):$(RESET)"
	@echo "  Kong Gateway:     http://localhost:8000"
	@echo "  Kong Admin:       http://localhost:8001"
	@echo "  Keycloak:         http://localhost:8080 (admin/admin123)"
	@echo "  NATS Monitoring:  http://localhost:8222"
	@echo "  Grafana:          http://localhost:3000 (admin/admin)"
	@echo "  MinIO Console:    http://localhost:9001 (minioadmin/minioadmin123)"

# Individual component deployments
deploy-namespaces: check-deps ## Create Kubernetes namespaces
	@echo "$(YELLOW)Creating namespaces...$(RESET)"
	@kubectl apply -f 00-namespaces/namespaces.yaml
	@echo "$(GREEN)✓ Namespaces created$(RESET)"

deploy-cilium: deploy-namespaces ## Deploy Cilium CNI with Gateway API support
	@echo "$(YELLOW)Installing Cilium CNI...$(RESET)"
ifeq ($(CLUSTER_TYPE),minikube)
	@minikube ssh -- sudo mount bpffs -t bpf /sys/fs/bpf 2>/dev/null || true
endif
	@cd 01-cilium && ./install.sh
	@echo "$(YELLOW)Waiting for Cilium to be ready...$(RESET)"
	@kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
	@echo "$(GREEN)✓ Cilium installed and ready$(RESET)"

deploy-storage: deploy-namespaces ## Deploy storage components (PostgreSQL, Redis, MinIO)
	@echo "$(YELLOW)Deploying storage components...$(RESET)"
	@kubectl apply -f 02-storage/
	@echo "$(YELLOW)Waiting for storage to be ready...$(RESET)"
	@kubectl wait --for=condition=ready pod -l app=postgres -n storage --timeout=300s || true
	@kubectl wait --for=condition=ready pod -l app=redis -n storage --timeout=300s || true
	@kubectl wait --for=condition=ready pod -l app=minio -n storage --timeout=300s || true
	@echo "$(GREEN)✓ Storage components deployed$(RESET)"

deploy-nats: deploy-namespaces ## Deploy NATS message broker
	@echo "$(YELLOW)Deploying NATS...$(RESET)"
	@helm repo add nats https://nats-io.github.io/k8s/helm/charts/ || true
	@helm repo update
	@helm upgrade --install nats nats/nats \
		--namespace messaging \
		--create-namespace \
		--values 03-nats/values.yaml \
		--version $(NATS_VERSION) \
		--wait \
		--timeout 10m
	@kubectl apply -f 03-nats/nats-cluster.yaml
	@echo "$(GREEN)✓ NATS deployed$(RESET)"

deploy-keycloak: deploy-storage ## Deploy Keycloak IAM
	@echo "$(YELLOW)Deploying Keycloak...$(RESET)"
	@kubectl apply -f 04-keycloak/keycloak.yaml
	@echo "$(YELLOW)Waiting for Keycloak to be ready...$(RESET)"
	@kubectl wait --for=condition=ready pod -l app=keycloak -n iam --timeout=300s
	@echo "$(GREEN)✓ Keycloak deployed$(RESET)"

deploy-kong: deploy-storage deploy-keycloak ## Deploy Kong Gateway
	@echo "$(YELLOW)Deploying Kong Gateway...$(RESET)"
	@helm repo add kong https://charts.konghq.com || true
	@helm repo update
	@helm upgrade --install kong kong/kong \
		--namespace kong \
		--create-namespace \
		--values 05-kong/values.yaml \
		--version $(KONG_VERSION) \
		--wait \
		--timeout 10m
	@sleep 30  # Give Kong time to initialize
	@kubectl apply -f 05-kong/plugins.yaml || true
	@echo "$(GREEN)✓ Kong Gateway deployed$(RESET)"

deploy-services: deploy-nats deploy-kong ## Deploy Zama microservices
	@echo "$(YELLOW)Deploying Zama microservices...$(RESET)"
	@kubectl apply -f 06-services/
	@echo "$(YELLOW)Waiting for services to be ready...$(RESET)"
	@kubectl wait --for=condition=ready pod -l tier=api -n zama-system --timeout=300s || true
	@echo "$(GREEN)✓ Zama services deployed$(RESET)"

deploy-policies: deploy-cilium deploy-services ## Apply network policies
	@echo "$(YELLOW)Applying network policies...$(RESET)"
	@kubectl apply -f 07-policies/
	@echo "$(GREEN)✓ Network policies applied$(RESET)"

deploy-monitoring: deploy-services ## Deploy monitoring stack
	@echo "$(YELLOW)Deploying monitoring stack...$(RESET)"
	@kubectl apply -f 08-monitoring/
	@echo "$(YELLOW)Waiting for monitoring to be ready...$(RESET)"
	@kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s || true
	@kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s || true
	@echo "$(GREEN)✓ Monitoring stack deployed$(RESET)"

# Utility targets
port-forward: ## Start port forwarding for local access
	@echo "$(YELLOW)Starting port forwarding...$(RESET)"
	@./port-forward.sh

test: ## Run deployment tests
	@echo "$(YELLOW)Running tests...$(RESET)"
	@./test.sh

test-load: ## Run load tests
	@echo "$(YELLOW)Running load tests...$(RESET)"
	@./test.sh load

test-security: ## Run security tests
	@echo "$(YELLOW)Running security tests...$(RESET)"
	@./test.sh security

# Management targets
logs: ## Show logs for all Zama services
	@echo "$(CYAN)Zama Services Logs:$(RESET)"
	@echo ""
	@echo "$(YELLOW)Kong Gateway:$(RESET)"
	@kubectl logs -n kong deployment/kong-kong --tail=10 || true
	@echo ""
	@echo "$(YELLOW)Job Submission Service:$(RESET)"
	@kubectl logs -n zama-system deployment/job-submission-service --tail=10 || true
	@echo ""
	@echo "$(YELLOW)Keycloak:$(RESET)"
	@kubectl logs -n iam deployment/keycloak --tail=10 || true

logs-follow: ## Follow logs for a specific service (usage: make logs-follow SERVICE=kong)
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)Error: Please specify SERVICE (kong, keycloak, nats, etc.)$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Following logs for $(SERVICE)...$(RESET)"
	@case "$(SERVICE)" in \
		kong) kubectl logs -n kong deployment/kong-kong -f ;; \
		keycloak) kubectl logs -n iam deployment/keycloak -f ;; \
		nats) kubectl logs -n messaging sts/nats -f ;; \
		postgres) kubectl logs -n storage sts/postgres -f ;; \
		redis) kubectl logs -n storage sts/redis -f ;; \
		minio) kubectl logs -n storage sts/minio -f ;; \
		job-submission) kubectl logs -n zama-system deployment/job-submission-service -f ;; \
		job-processing) kubectl logs -n zama-system deployment/job-processing-service -f ;; \
		blockchain) kubectl logs -n zama-system deployment/blockchain-service -f ;; \
		metering) kubectl logs -n zama-system deployment/metering-service -f ;; \
		*) echo "$(RED)Unknown service: $(SERVICE)$(RESET)" ;; \
	esac

scale-up: ## Scale up services for high load
	@echo "$(YELLOW)Scaling up services...$(RESET)"
	@kubectl scale deployment kong-kong -n kong --replicas=3
	@kubectl scale deployment job-processing-service -n zama-system --replicas=5
	@kubectl scale statefulset nats -n messaging --replicas=1
	@echo "$(GREEN)✓ Services scaled up$(RESET)"

scale-down: ## Scale down services to save resources
	@echo "$(YELLOW)Scaling down services...$(RESET)"
	@kubectl scale deployment kong-kong -n kong --replicas=1
	@kubectl scale deployment job-processing-service -n zama-system --replicas=2
	@kubectl scale statefulset nats -n messaging --replicas=1
	@echo "$(GREEN)✓ Services scaled down$(RESET)"

restart-services: ## Restart all Zama services
	@echo "$(YELLOW)Restarting Zama services...$(RESET)"
	@kubectl rollout restart deployment/kong-kong -n kong
	@kubectl rollout restart deployment/keycloak -n iam
	@kubectl rollout restart deployment -n zama-system
	@echo "$(GREEN)✓ Services restarted$(RESET)"

update-images: ## Update container images to latest versions
	@echo "$(YELLOW)Updating container images...$(RESET)"
	@kubectl set image deployment/job-submission-service service=zama/job-submission:latest -n zama-system
	@kubectl set image deployment/job-processing-service worker=zama/job-processing:latest -n zama-system
	@kubectl set image deployment/blockchain-service service=zama/blockchain-service:latest -n zama-system
	@kubectl set image deployment/metering-service service=zama/metering-service:latest -n zama-system
	@echo "$(GREEN)✓ Images updated$(RESET)"

# Maintenance targets
backup: ## Create backup of critical data
	@echo "$(YELLOW)Creating backup...$(RESET)"
	@mkdir -p backups/$(shell date +%Y%m%d_%H%M%S)
	@kubectl exec -n storage sts/postgres -- pg_dumpall -U postgres > backups/$(shell date +%Y%m%d_%H%M%S)/postgres_backup.sql
	@echo "$(GREEN)✓ Backup created in backups/$(shell date +%Y%m%d_%H%M%S)/$(RESET)"

upgrade-helm: ## Upgrade Helm charts to latest versions
	@echo "$(YELLOW)Upgrading Helm charts...$(RESET)"
	@helm repo update
	@helm upgrade kong kong/kong -n kong --values 05-kong/values.yaml
	@helm upgrade nats nats/nats -n messaging --values 03-nats/values.yaml
	@echo "$(GREEN)✓ Helm charts upgraded$(RESET)"

# Cleanup targets
clean: ## Remove the entire Zama deployment
	@echo "$(RED)This will delete the entire Zama Jobs API deployment!$(RESET)"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@./cleanup.sh

clean-force: ## Force remove everything without confirmation
	@echo "$(RED)Force cleaning deployment...$(RESET)"
	@kubectl delete -f 06-services/ --ignore-not-found=true
	@helm uninstall kong -n kong --ignore-not-found
	@kubectl delete -f 04-keycloak/ --ignore-not-found=true
	@helm uninstall nats -n messaging --ignore-not-found
	@kubectl delete -f 03-nats/nats-cluster.yaml --ignore-not-found=true
	@kubectl delete -f 02-storage/ --ignore-not-found=true
	@kubectl delete -f 08-monitoring/ --ignore-not-found=true
	@kubectl delete -f 07-policies/ --ignore-not-found=true
	@kubectl delete -f 00-namespaces/namespaces.yaml --ignore-not-found=true
	@echo "$(GREEN)✓ Deployment cleaned$(RESET)"

clean-pvcs: ## Remove persistent volume claims (will delete data!)
	@echo "$(RED)This will delete all persistent data!$(RESET)"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@kubectl delete pvc --all -n storage --ignore-not-found=true
	@kubectl delete pvc --all -n messaging --ignore-not-found=true
	@kubectl delete pvc --all -n kong --ignore-not-found=true
	@kubectl delete pvc --all -n iam --ignore-not-found=true
	@kubectl delete pvc --all -n zama-system --ignore-not-found=true
	@echo "$(GREEN)✓ PVCs deleted$(RESET)"

# Development targets
dev-setup: deploy port-forward ## Quick development setup
	@echo "$(GREEN)Development environment ready!$(RESET)"
	@echo "Services are accessible at:"
	@echo "  Kong Gateway: http://localhost:8000"
	@echo "  Kong Admin: http://localhost:8001"
	@echo "  Keycloak: http://localhost:8080"

dev-reset: clean-force deploy-namespaces deploy-storage deploy-cilium deploy-nats deploy-keycloak deploy-kong deploy-services port-forward ## Reset development environment

# Monitoring targets
dashboard: ## Open monitoring dashboards
	@echo "$(YELLOW)Opening monitoring dashboards...$(RESET)"
	@open http://localhost:3000 || echo "Open http://localhost:3000 manually"
	@open http://localhost:8222 || echo "Open http://localhost:8222 manually"
	@open http://localhost:12000 || echo "Open http://localhost:12000 manually"

cilium-status: ## Show Cilium status
	@echo "$(CYAN)Cilium Status:$(RESET)"
	@cilium status || kubectl get pods -n kube-system -l k8s-app=cilium

kong-status: ## Show Kong status
	@echo "$(CYAN)Kong Status:$(RESET)"
	@curl -s http://localhost:8001/status 2>/dev/null | jq '.' || echo "Kong admin API not accessible"

# Troubleshooting targets
debug: ## Debug deployment issues
	@echo "$(CYAN)Debug Information:$(RESET)"
	@echo ""
	@echo "$(YELLOW)Cluster Info:$(RESET)"
	@kubectl cluster-info
	@echo ""
	@echo "$(YELLOW)Failed Pods:$(RESET)"
	@kubectl get pods --all-namespaces | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" || echo "No failed pods"
	@echo ""
	@echo "$(YELLOW)Resource Usage:$(RESET)"
	@kubectl top nodes 2>/dev/null || echo "Metrics server not available"
	@echo ""
	@echo "$(YELLOW)Events:$(RESET)"
	@kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp | tail -10

fix-permissions: ## Fix common permission issues
	@echo "$(YELLOW)Fixing permissions...$(RESET)"
	@chmod +x *.sh 01-cilium/install.sh
	@echo "$(GREEN)✓ Permissions fixed$(RESET)"

# Documentation targets
docs: ## Open documentation
	@echo "$(CYAN)Opening documentation...$(RESET)"
	@open README.md DEPLOYMENT_GUIDE.md || echo "Open README.md and DEPLOYMENT_GUIDE.md manually"

# Version information
version: ## Show component versions
	@echo "$(CYAN)Component Versions:$(RESET)"
	@echo "Cilium: $(CILIUM_VERSION)"
	@echo "Kong: $(KONG_VERSION)"
	@echo "Keycloak: $(KEYCLOAK_VERSION)"
	@echo "NATS: $(NATS_VERSION)"
	@echo ""
	@echo "$(CYAN)Deployed Versions:$(RESET)"
	@kubectl get pods -o jsonpath="{range .items[*]}{.metadata.name}{'\t'}{.spec.containers[*].image}{'\n'}{end}" --all-namespaces | grep -E "(kong|keycloak|nats|cilium)" | sort || true