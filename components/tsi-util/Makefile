TSI_VERSION=$(shell cat ../../tsi-version.txt)
GIT_COMMIT_SHA="$(shell git rev-parse --short HEAD 2>/dev/null)"
GIT_REMOTE_URL="$(shell git config --get remote.origin.url 2>/dev/null)"
BUILD_DATE="$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")"
BINARY_NAME="tsi-util"
REPO ?= tsidentity
IMAGE := $(REPO)/$(BINARY_NAME):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE := $(REPO)/$(BINARY_NAME):$(TSI_VERSION)
LATEST := $(REPO)/$(BINARY_NAME):latest

all: docker timestamp

allpush: docker docker-push timestamp

fastpush: fast docker-push timestamp

fast:
	docker build -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	docker tag $(IMAGE) $(LATEST)
	date

docker:
	docker build --no-cache -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	docker tag $(IMAGE) $(LATEST)

docker-push:
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)
	docker push $(LATEST)

timestamp:
	date

.PHONY: all fast allpush fastpush docker docker-push timestamp
