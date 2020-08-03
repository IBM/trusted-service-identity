TSI_VERSION=$(shell cat ../../tsi-version.txt)
GIT_COMMIT_SHA="$(shell git rev-parse --short HEAD 2>/dev/null)"
GIT_REMOTE_URL="$(shell git config --get remote.origin.url 2>/dev/null)"
BUILD_DATE="$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")"
BINARY_NAME="tsi-jwt-init"
REPO ?= trustedseriviceidentity
IMAGE := $(REPO)/$(BINARY_NAME):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE := $(REPO)/$(BINARY_NAME):$(TSI_VERSION)

all: docker timestamp

allpush: docker docker-push timestamp

fastpush: fast docker-push timestamp

fast:
	docker build -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	date

docker:
	docker build --no-cache -t $(IMAGE) -f Dockerfile .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)

docker-push:
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)

timestamp:
	date

.PHONY: all fast allpush fastpush docker docker-push timestamp
