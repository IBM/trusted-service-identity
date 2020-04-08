GOPACKAGES=$(shell go list ./... | grep -v /vendor/) # With glide: GOPACKAGES=$(shell glide novendor)
GOFILES=$(shell find . -type f -name '*.go' -not -path "./vendor/*")

GIT_COMMIT_SHA=$(shell git rev-parse --short HEAD 2>/dev/null)
GIT_REMOTE_URL=$(shell git config --get remote.origin.url 2>/dev/null)
BUILD_DATE=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
BINARY_NAME=ti-webhook
REPO ?= trustedseriviceidentity
IMAGE := $(REPO)/$(BINARY_NAME):$(GIT_COMMIT_SHA)
MUTABLE_IMAGE := $(REPO)/$(BINARY_NAME):v1.4
GOARCH=$(shell go env GOARCH)

.PHONY: all fast test-deps build-deps fmt vet lint get-deps test build docker docker-push dep

all: dep get-deps fmt test build docker timestamp

fast: test build docker docker-push timestamp

dep:
	go mod tidy

get-deps: test-deps build-deps

test-deps: build-deps
	go get -u golang.org/x/lint/golint
	go get github.com/stretchr/testify/assert
	go get github.com/pierrre/gotestcover

test: test-deps
	$(GOPATH)/bin/gotestcover -v -coverprofile=cover.out ${GOPACKAGES}

build:
	CGO_ENABLED=0 GOOS=linux GOARCH=${GOARCH} go build -installsuffix cgo -o $(BINARY_NAME) -v

docker: build
	docker build --no-cache -t $(IMAGE) .
	docker tag $(IMAGE) $(MUTABLE_IMAGE)
	rm $(BINARY_NAME)

docker-push:
	docker push $(IMAGE)
	docker push $(MUTABLE_IMAGE)

timestamp:
	date

build-deps: dep
	go mod vendor

fmt:
	@if [ -n "$$(gofmt -l ${GOFILES})" ]; then echo 'Please run gofmt -l -w ${GOFILES} on your code.' && exit 1; fi

vet:
	@set -e; for LINE in ${GOPACKAGES}; do go vet $${LINE} ; done

lint:
	@set -e; for LINE in ${GOPACKAGES}; do golint -set_exit_status=true $${LINE} ; done
