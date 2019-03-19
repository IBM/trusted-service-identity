GOPACKAGES=$(shell go list ./... | grep -v /vendor/) # With glide: GOPACKAGES=$(shell glide novendor)
GOFILES=$(shell find . -type f -name '*.go' -not -path "./vendor/*")

GIT_COMMIT_SHA="$(shell git rev-parse --short HEAD 2>/dev/null)"
GIT_REMOTE_URL="$(shell git config --get remote.origin.url 2>/dev/null)"
BUILD_DATE="$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")"
BINARY_NAME="ti-revoker"
REPO ?= res-kompass-kompass-docker-local.artifactory.swg-devops.com
IMAGE := $(REPO)/$(BINARY_NAME):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE := $(REPO)/$(BINARY_NAME):v0.12

.PHONY: all test-deps build-deps fmt vet lint get-deps test build docker

all: build docker docker-push timestamp

fast: build
	docker build -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)
	date

build:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -installsuffix cgo -o $(BINARY_NAME) -v

docker: build
	docker build --no-cache -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	rm $(BINARY_NAME)

docker-push:
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)

timestamp:
	date

fmt:
	@if [ -n "$$(gofmt -l ${GOFILES})" ]; then echo 'Please run gofmt -l -w on your code.' && exit 1; fi

vet:
	@set -e; for LINE in ${GOPACKAGES}; do go vet $${LINE} ; done

lint:
	@set -e; for LINE in ${GOPACKAGES}; do golint -set_exit_status=true $${LINE} ; done
