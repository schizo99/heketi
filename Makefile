#
# Based on http://chrismckenzie.io/post/deploying-with-golang/
#

APP_NAME := heketi
CLIENT_PKG_NAME := heketi-client
SHA := $(shell git rev-parse --short HEAD)
BRANCH := $(subst /,-,$(shell git rev-parse --abbrev-ref HEAD))
VER := $(shell git describe --match='v[0-9].[0-9].[0-9]')
TAG := $(shell git tag --points-at HEAD 'v[0-9].[0-9].[0-9]' | tail -n1)
GOARCH := $(shell go env GOARCH)
GOOS := $(shell go env GOOS)
GOHOSTARCH := $(shell go env GOHOSTARCH)
GOHOSTOS := $(shell go env GOHOSTOS)
GOBUILDFLAGS :=
ifeq ($(GOOS),$(GOHOSTOS))
ifeq ($(GOARCH),$(GOHOSTARCH))
	GOBUILDFLAGS :=-i
endif
endif
GLIDEPATH := $(shell command -v glide 2> /dev/null)
DIR=.

ifeq (master,$(BRANCH))
	VERSION = $(VER)
else
ifeq ($(VER),$(TAG))
	VERSION = $(VER)
else
	VERSION = $(VER)-$(BRANCH)
endif
endif

# Go setup
GO=go

# Sources and Targets
EXECUTABLES :=$(APP_NAME)
# Build Binaries setting main.version and main.build vars
LDFLAGS :=-ldflags "-X main.HEKETI_VERSION=$(VERSION) -extldflags '-z relro -z now'"
# Package target
PACKAGE :=$(DIR)/dist/$(APP_NAME)-$(VERSION).$(GOOS).$(GOARCH).tar.gz
CLIENT_PACKAGE :=$(DIR)/dist/$(APP_NAME)-client-$(VERSION).$(GOOS).$(GOARCH).tar.gz
DEPS_TARBALL :=$(DIR)/dist/$(APP_NAME)-deps-$(VERSION).tar.gz

.DEFAULT: all

all: server client

# print the version
version:
	@echo $(VERSION)

# print the name of the app
name:
	@echo $(APP_NAME)

# print the package path
package:
	@echo $(PACKAGE)

heketi: vendor glide.lock
	go build $(GOBUILDFLAGS) $(LDFLAGS) -o $(APP_NAME)

server: heketi

vendor:
ifndef GLIDEPATH
	$(info Please install glide.)
	$(info Install it using your package manager or)
	$(info by running: curl https://glide.sh/get | sh.)
	$(info )
	$(error glide is required to continue)
endif
	echo "Installing vendor directory"
	glide install -v

glide.lock: glide.yaml
	echo "Glide.yaml has changed, updating glide.lock"
	glide update -v

client: vendor glide.lock
	@$(MAKE) -C client/cli/go

run: server
	./$(APP_NAME)

test: vendor glide.lock
	./test.sh $(TESTOPTIONS)

clean:
	@echo Cleaning Workspace...
	rm -rf $(APP_NAME)
	rm -rf dist coverage packagecover.out
	@$(MAKE) -C client/cli/go clean

clean_vendor:
	rm -rf vendor

$(PACKAGE): all
	@echo Packaging Binaries...
	@mkdir -p tmp/$(APP_NAME)
	@cp $(APP_NAME) tmp/$(APP_NAME)/
	@cp client/cli/go/heketi-cli tmp/$(APP_NAME)/
	@cp etc/heketi.json tmp/$(APP_NAME)/
	@mkdir -p $(DIR)/dist/
	tar -czf $@ -C tmp $(APP_NAME);
	@rm -rf tmp
	@echo
	@echo Package $@ saved in dist directory

$(CLIENT_PACKAGE): all
	@echo Packaging client Binaries...
	@mkdir -p tmp/$(CLIENT_PKG_NAME)/bin
	@mkdir -p tmp/$(CLIENT_PKG_NAME)/share/heketi/openshift/templates
	@mkdir -p tmp/$(CLIENT_PKG_NAME)/share/heketi/kubernetes
	@cp client/cli/go/topology-sample.json tmp/$(CLIENT_PKG_NAME)/share/heketi
	@cp client/cli/go/heketi-cli tmp/$(CLIENT_PKG_NAME)/bin
	@cp extras/openshift/templates/* tmp/$(CLIENT_PKG_NAME)/share/heketi/openshift/templates
	@cp extras/kubernetes/* tmp/$(CLIENT_PKG_NAME)/share/heketi/kubernetes
	@mkdir -p $(DIR)/dist/
	tar -czf $@ -C tmp $(CLIENT_PKG_NAME);
	@rm -rf tmp
	@echo
	@echo Package $@ saved in dist directory

deps_tarball: $(DEPS_TARBALL)

$(DEPS_TARBALL): clean clean_vendor vendor glide.lock
	@echo Creating dependency tarball...
	@mkdir -p $(DIR)/dist/
	tar -czf $@ -C vendor .

dist: $(PACKAGE) $(CLIENT_PACKAGE)

linux_amd64_dist:
	GOOS=linux GOARCH=amd64 $(MAKE) dist

linux_arm_dist:
	GOOS=linux GOARCH=arm $(MAKE) dist

linux_arm64_dist:
	GOOS=linux GOARCH=arm64 $(MAKE) dist

darwin_amd64_dist:
	GOOS=darwin GOARCH=amd64 $(MAKE) dist

release: deps_tarball darwin_amd64_dist linux_arm64_dist linux_arm_dist linux_amd64_dist

.PHONY: server client test clean name run version release \
	darwin_amd64_dist linux_arm_dist linux_amd64_dist linux_arm64_dist \
	heketi clean_vendor deps_tarball all dist
