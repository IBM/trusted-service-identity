TSI_VERSION=$(shell cat ../../tsi-version.txt)
GIT_COMMIT_SHA="$(shell git rev-parse --short HEAD 2>/dev/null)"
GIT_REMOTE_URL="$(shell git config --get remote.origin.url 2>/dev/null)"
BUILD_DATE="$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")"
BINARY_NAME_PUB="jss-server-pub"
BINARY_NAME_PRIV="jss-server-priv"
REPO ?= trustedseriviceidentity
IMAGE_PUB := $(REPO)/$(BINARY_NAME_PUB):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE_PUB := $(REPO)/$(BINARY_NAME_PUB):$(TSI_VERSION)
IMAGE_PRIV := $(REPO)/$(BINARY_NAME_PRIV):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE_PRIV := $(REPO)/$(BINARY_NAME_PRIV):$(TSI_VERSION)

all: docker timestamp

allpush: docker docker-push timestamp

fastpush:  fast docker-push timestamp

fast:
	docker build -t $(IMAGE_PUB) -f Dockerfile.pub .
	docker tag $(IMAGE_PUB) $(MUTABLE_IMAGE_PUB)
	docker build -t $(IMAGE_PRIV) -f Dockerfile.privsock .
	docker tag $(IMAGE_PRIV) $(MUTABLE_IMAGE_PRIV)
	date

docker:
	docker build --no-cache -t $(IMAGE_PUB) -f Dockerfile.pub .
	docker tag $(IMAGE_PUB) $(MUTABLE_IMAGE_PUB)
	docker build --no-cache -t $(IMAGE_PRIV) -f Dockerfile.privsock .
	docker tag $(IMAGE_PRIV) $(MUTABLE_IMAGE_PRIV)

docker-push:
	docker push $(IMAGE_PUB)
	docker push $(MUTABLE_IMAGE_PUB)
	docker push $(IMAGE_PRIV)
	docker push $(MUTABLE_IMAGE_PRIV)

timestamp:
	date

.PHONY: all fast allpush fastpush docker docker-push timestamp
