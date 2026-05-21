.PHONY: help kind-create kind-delete image-build image-load

help:
	@echo "Targets:"
	@echo "  kind-create   - create Kind cluster from hack/kind-config.yaml"
	@echo "  kind-delete   - delete the cluster named spice-gitops"
	@echo "  image-build   - docker build control plane image"
	@echo "  image-load    - kind load docker-image (after image-build)"

CLUSTER_NAME ?= spice-gitops

kind-create:
	kind create cluster --name $(CLUSTER_NAME) --config hack/kind-config.yaml

kind-delete:
	kind delete cluster --name $(CLUSTER_NAME)

image-build:
	docker build -t spice-control-plane:latest apps/control-plane

image-load: image-build
	kind load docker-image spice-control-plane:latest --name $(CLUSTER_NAME)
