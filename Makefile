# ==============================================================================
# SMART MANUFACTURING MLOPS PLATFORM - WORKFLOW MAKEFILE
# ==============================================================================

.PHONY: help deploy infra ansible apps test train failover-drill compose-up compose-down compile-kubeflow clean

help: ## Show this help menu
	@echo "=================================================================="
	@echo " Smart Manufacturing MLOps & Multi-Cloud Automation"
	@echo "=================================================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: ## One-click deployment across all layers (Infra, Ansible, GitOps, Models, Failover)
	@./deploy.sh --all

infra: ## Provision AWS and GCP clusters via Terraform
	@./deploy.sh --infra

ansible: ## Run Ansible GPU node & cluster bootstrap playbooks
	@./deploy.sh --ansible

apps: ## Deploy ArgoCD GitOps apps and Kubernetes overlays
	@./deploy.sh --apps

test: ## Run unit tests, API tests, and failover logic tests
	@pytest tests/ -v --cov=src --cov-report=term-missing

train: ## Run local/GPU model training and MLflow tracking
	@python3 -m src.training.train_sensor --epochs 10
	@python3 -m src.training.train_vision --epochs 5

compile-kubeflow: ## Compile Kubeflow Pipelines v2 pipeline to YAML
	@python3 kubeflow/pipeline.py

failover-drill: ## Execute automated multi-cloud failover simulation
	@./deploy.sh --failover-test

compose-up: ## Start local simulated multi-cloud environment with MinIO, MLflow, and APIs
	@docker compose -f docker/docker-compose.yml up -d --build

compose-down: ## Tear down local simulated environment
	@docker compose -f docker/docker-compose.yml down -v

clean: ## Remove temporary build and test cache artifacts
	@rm -rf .pytest_cache .coverage coverage.xml dist build *.egg-info
	@find . -type d -name "__pycache__" -exec rm -rf {} +
