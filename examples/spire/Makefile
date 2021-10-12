.PHONY: bin/mars container-mars

GIT_COMMIT_SHA="$(shell git rev-parse --short HEAD 2>/dev/null)"
REPO ?= tsidentity
MARS_IMG_NAME ?= mars-demo
VERSION=$(shell cat ../../tsi-version.txt)
# GO_FILES := $(shell find . -type f -name '*.go' -not -name '*_test.go' -not -path './vendor/*')

MARS_IMG := $(REPO)/$(MARS_IMG_NAME):$(GIT_COMMIT_SHA)
MARS_IMG_MUTABLE := $(REPO)/$(MARS_IMG_NAME):$(VERSION)
MARS_IMG_LATEST := $(REPO)/$(MARS_IMG_NAME):latest

all: bin/mars container-mars

bin/mars:
	docker build --no-cache -t $(MARS_IMG) -f Dockerfile.mars .
	docker tag $(MARS_IMG) $(MARS_IMG_MUTABLE)
	docker tag $(MARS_IMG) $(MARS_IMG_LATEST)

container-mars:
	docker push $(MARS_IMG)
	docker push $(MARS_IMG_MUTABLE)
	docker push $(MARS_IMG_LATEST)

# vendor:
# 	go mod tidy
# 	go mod vendor
