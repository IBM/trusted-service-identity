GIT_COMMIT_SHA="$(shell git rev-parse --short HEAD 2>/dev/null)"
GIT_REMOTE_URL="$(shell git config --get remote.origin.url 2>/dev/null)"
BUILD_DATE="$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")"
BINARY_NAME="ti-gen-vault-cert"
REPO ?= trustedseriviceidentity
IMAGE := $(REPO)/$(BINARY_NAME):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE := $(REPO)/$(BINARY_NAME):v1.2
ARCH=$(shell if test `uname -m` = "x86_64"; then echo amd64 ; else echo `uname -m`; fi;)

all: docker docker-push timestamp

fast:
	docker build --build-arg ARCH=${ARCH} -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)
	date

docker:
	docker build --no-cache --build-arg ARCH=${ARCH} -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)

docker-push:
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)

timestamp:
	date

.PHONY: all fast docker docker-push timestamp
