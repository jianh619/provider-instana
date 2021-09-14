# Set the shell to bash always
SHELL := /bin/bash

# Options
ORG_NAME=quay.io/hjwilson19560
PROVIDER_NAME=provider-instana
JOB_NAME=instana-install

build: generate
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o ./bin/$(PROVIDER_NAME)-controller cmd/provider/main.go

image: generate
	docker build . -t $(ORG_NAME)/$(PROVIDER_NAME):latest -f cluster/Dockerfile
	docker build . -t $(ORG_NAME)/$(JOB_NAME):latest -f job/Dockerfile	

image-push:
	docker push $(ORG_NAME)/$(PROVIDER_NAME):latest
	docker tag $(ORG_NAME)/$(PROVIDER_NAME):latest $(ORG_NAME)/$(PROVIDER_NAME):v0.0.1	
	docker push $(ORG_NAME)/$(PROVIDER_NAME):v0.0.1
	docker push $(ORG_NAME)/$(JOB_NAME):latest

run: generate
	kubectl apply -f package/crds/ -R
	go run cmd/provider/main.go -d

all: image image-push

generate:
	go generate ./...
	@find package/crds -name *.yaml -exec sed -i.sed -e '1,2d' {} \;
	@find package/crds -name *.yaml.sed -delete

lint:
	$(LINT) run

tidy:
	go mod tidy

test:
	go test -v ./...

# Tools

KIND=$(shell which kind)
LINT=$(shell which golangci-lint)

.PHONY: generate tidy lint clean build image all run

