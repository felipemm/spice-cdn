.PHONY: help kind-create kind-delete image-build image-load-local image-load install-help gitops-push-gitea

GITOPS_WORKDIR ?= $(CURDIR)/gitea/gitops

help:
	@echo "Targets:"
	@echo "  kind-create        - create Kind cluster from hack/kind-config.yaml"
	@echo "  kind-delete        - delete the cluster named spice-gitops"
	@echo "  image-build        - docker build local tag spice-control-plane:latest (optional dev)"
	@echo "  image-load-local   - kind load that local image (only if you override Helm away from GHCR)"
	@echo "  image-load         - alias for image-load-local"
	@echo "  install-help       - scripts/install.sh --help"
	@echo "  gitops-push-gitea  - materialize and push GitOps tree to local Gitea (Kind lab)"

install-help:
	@./scripts/install.sh --help

CLUSTER_NAME ?= spice-gitops

kind-create:
	kind create cluster --name $(CLUSTER_NAME) --config hack/kind-config.yaml

kind-delete:
	kind delete cluster --name $(CLUSTER_NAME)

image-build:
	docker build -t spice-control-plane:latest -f apps/control-plane/Dockerfile apps/control-plane
	docker tag spice-control-plane:latest spice-cp-local:lab

image-load-local: image-build
	kind load docker-image spice-cp-local:lab --name $(CLUSTER_NAME)

image-load: image-load-local

gitops-push-gitea:
	@./scripts/push-gitea-gitops.sh
