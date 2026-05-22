.PHONY: help kind-create kind-delete image-build image-load-local image-load install-help

help:
	@echo "Targets:"
	@echo "  kind-create        - create Kind cluster from hack/kind-config.yaml"
	@echo "  kind-delete        - delete the cluster named spice-gitops"
	@echo "  image-build        - docker build local tag spice-control-plane:latest (optional dev)"
	@echo "  image-load-local   - kind load that local image (only if you override Helm away from GHCR)"
	@echo "  image-load         - alias for image-load-local"
	@echo "  install-help       - scripts/install.sh --help"

install-help:
	@./scripts/install.sh --help

CLUSTER_NAME ?= spice-gitops

kind-create:
	kind create cluster --name $(CLUSTER_NAME) --config hack/kind-config.yaml

kind-delete:
	kind delete cluster --name $(CLUSTER_NAME)

image-build:
	docker build -t spice-control-plane:latest apps/control-plane

image-load-local: image-build
	kind load docker-image spice-control-plane:latest --name $(CLUSTER_NAME)

image-load: image-load-local
