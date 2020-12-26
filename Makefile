# kernel-style V=1 build verbosity
ifeq ("$(origin V)", "command line")
  BUILD_VERBOSE = $(V)
endif

ifeq ($(BUILD_VERBOSE),1)
  Q =
else
  Q = @
endif

PROJECT_ROOT             = $(shell pwd)

APP_TITLE                = k3x
APP_ID                   = com.github.inercia.$(APP_TITLE)

APP_SRC_PY               = $(wildcard src/*.py)
APP_SRC_MESONS           = $(wildcard */meson.build) $(wildcard */*/meson.build)
APP_SRC_DATA             = $(wildcard data/*.in) $(wildcard data/*.xml)

FLATPAK_SDK              = org.gnome.Sdk
FLATPAK_RUNTIME          = org.gnome.Platform
FLATPAK_RUNTIME_VERSION  = 3.36

METAINFO_FILE            = data/com.github.inercia.k3x.appdata.xml.in

FLATPAK_BASE_APP         = io.elementary.BaseApp
FLATPAK_BASE_VERSION     = juno-19.08

FLATPAK_MANIFEST         = $(PROJECT_ROOT)/com.github.inercia.k3x.json
BUILD_ROOT               = $(PROJECT_ROOT)/.flatpak-builder

FLATPAK_BUNDLE          ?= $(PROJECT_ROOT)/$(APP_ID).flatpak

FLATPAK_RUN_COMMAND     ?= k3x

STATE_DIR                = $(BUILD_ROOT)
CCACHE_DIR               = $(BUILD_ROOT)/ccache
BUILD_DIR               ?= $(BUILD_ROOT)/build/staging
RELEASE_DIR             ?= $(BUILD_ROOT)/build/release
FLATPAK_REPO_DIR        ?= $(BUILD_ROOT)/repo

FLATPAK_RUN_ARGS         = \
	--nofilesystem=host \
	--env=NOCONFIGURE=1 \
	--env=LANG=en_US.UTF-8 \
	--env=USER=$$USER \
	--env=HOME=$$HOME \
	--env=PATH=/app/bin:/usr/bin:/bin \
	--env=TERM=xterm-256color \
	--env=V=0 \
	--env=CCACHE_DIR=$(CCACHE_DIR) \
	--filesystem=$(BUILD_ROOT) \
	--filesystem=$(PROJECT_ROOT) \
	--filesystem=$(BUILD_DIR)

FLATPAK_RUN_SHARES       = \
	--share=ipc \
	--socket=fallback-x11 \
	--share=network \
	--socket=wayland \
	--filesystem=xdg-run/dconf \
	--filesystem=~/.config/dconf:ro \
	--talk-name=ca.desrt.dconf \
	--talk-name=org.freedesktop.Notifications \
	--talk-name=org.kde.StatusNotifierWatcher \
	--talk-name=com.canonical.indicator.application \
	--talk-name=org.ayatana.indicator.application \
	--env=DCONF_USER_CONFIG_DIR=.config/dconf \
	--filesystem=home \
	--filesystem=/run/docker.sock

FLATPAK_BUILDER_ARGS        = \
	--arch=x86_64             \
	--ccache                  \
	--force-clean             \
	--state-dir $(STATE_DIR)  \
	--disable-updates

FLATPAK_BUILD_ARGS = \
	$(FLATPAK_RUN_ARGS) $(FLATPAK_RUN_SHARES) $(BUILD_DIR)

# the submodule for flathub
FLATHUB_DIR     = $(PROJECT_ROOT)/flathub
FLATHUB_PATCH   = $(PROJECT_ROOT)/build-aux/flathub-diff.patch


# pep8 ignores
PEP8_IGNORE = E402,E501,E722,E127,E501

# some git info
TAG            ?=
GIT_TAG_LATEST  = $(shell git describe --abbrev=0)
GIT_MODIFIED    = $(shell git ls-files -m)

NINJA_TARGET ?=


##############################
# Help                       #
##############################

RED=\033[1;31m
GRN=\033[1;32m
BLU=\033[1;34m
CYN=\033[1;36m
BLD=\033[1m
END=\033[0m

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##############################PROJECT_GIT_VERSION      = $(shell git describe --abbrev=0)

# Development
##############################
##@ Development

deps: ## Install all the required dependencies for building/running
	@printf "$(CYN)>>> $(GRN)Checking out submodules...$(END)\n"
	git submodule init
	git submodule update
	@printf "$(CYN)>>> $(GRN)Adding flatpak dependencies (apps, frameworks...)...$(END)\n"
	flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
	flatpak --user install -y flathub $(FLATPAK_RUNTIME)/x86_64/$(FLATPAK_RUNTIME_VERSION)
	flatpak --user install -y flathub $(FLATPAK_SDK)/x86_64/$(FLATPAK_RUNTIME_VERSION)
	flatpak --user install -y flathub $(FLATPAK_BASE_APP)/x86_64/$(FLATPAK_BASE_VERSION)

$(BUILD_DIR):
	@printf "$(CYN)>>> $(GRN)Creating build dir $(BUILD_DIR) ...$(END)\n"
	$(Q)mkdir -p $(BUILD_DIR)
	$(Q)-flatpak build-init $(BUILD_DIR) $(APP_ID) $(FLATPAK_SDK) $(FLATPAK_RUNTIME) $(FLATPAK_RUNTIME_VERSION)

$(BUILD_DIR)/build.ninja: $(BUILD_DIR) $(FLATPAK_MANIFEST) $(APP_SRC_MESONS)
	@printf "$(CYN)>>> $(GRN)Downloading dependencies (in build_dir=$(BUILD_DIR))...$(END)\n"
	$(Q)flatpak-builder $(FLATPAK_BUILDER_ARGS) --download-only --stop-at=k3x \
		$(BUILD_DIR) $(FLATPAK_MANIFEST)

	@printf "$(CYN)>>> $(GRN)Building dependencies (in build_dir=$(BUILD_DIR))...$(END)\n"
	$(Q)flatpak-builder $(FLATPAK_BUILDER_ARGS) --disable-download --stop-at=k3x \
		$(BUILD_DIR) $(FLATPAK_MANIFEST)

	@printf "$(CYN)>>> $(GRN)Building with meson (in build_dir=$(BUILD_DIR))...$(END)\n"
	$(Q)flatpak build --build-dir=$(BUILD_DIR) $(FLATPAK_BUILD_ARGS) meson $(PROJECT_ROOT) . --prefix=/app

.PHONY: build
build: pypi-dependencies.json $(BUILD_DIR)/build.ninja ## Build the application

##@ Local dev loop

.PHONY: run
run: $(BUILD_DIR)/build.ninja ## Run the application locally
	$(Q)cd $(BUILD_DIR) && \
		printf "$(CYN)>>> $(GRN)Running ninja (in build_dir=$(BUILD_DIR))...$(END)\n" && \
		flatpak build --build-dir=$(BUILD_DIR) $(FLATPAK_BUILD_ARGS) ninja

	$(Q)cd $(BUILD_DIR) && \
		printf "$(CYN)>>> $(GRN)Running ninja install (in build_dir=$(BUILD_DIR))...$(END)\n" && \
		flatpak build --build-dir=$(BUILD_DIR) $(FLATPAK_BUILD_ARGS) ninja install

	@printf "$(CYN)>>> $(GRN)Running $(FLATPAK_RUN_COMMAND) in the sandbox...$(END)\n"
	$(Q)flatpak-builder $(FLATPAK_RUN_ARGS) $(FLATPAK_RUN_SHARES) --run $(BUILD_DIR) $(FLATPAK_MANIFEST) \
		$(FLATPAK_RUN_COMMAND)

.PHONY: shell
shell: FLATPAK_RUN_COMMAND=bash
shell: run ## Run a shell in the sandbox

##############################
# Clean
##############################
##@ Development: clean

.PHONY: clean
clean: ## Clean build products
	@printf "$(CYN)>>> $(GRN)Doing a quick clean-up...$(END)\n"
	$(Q)rm -rf $(BUILD_DIR) $(RELEASE_DIR) $(FLATPAK_BUNDLE) pypi-dependencies.json

.PHONY: distclean
distclean: ## Clean-up everything
	@printf "$(CYN)>>> $(GRN)Cleaning everything...$(END)\n"
	$(Q)rm -rf $(BUILD_ROOT) $(FLATPAK_BUNDLE)

##############################
# Checks and tests
##############################

##@ Development: checks and tests

.PHONY: clean
check: pep8 ## Check code style

.PHONY: format
format:
	autopep8 --in-place --max-line-length=120 --ignore=$(PEP8_IGNORE) src/*.py

.PHONY: pep8
pep8:
	$(Q)find src -name \*.py -exec pycodestyle --ignore=$(PEP8_IGNORE) {} +

# checks that the version in meson.build matches the TAAG (or latest tag)
check-version:
	$(Q)[ -n "$(TAG)" ] || { printf "$(CYN)>>> $(RED)No TAG provided$(END)\n" ; exit 1 ; }
	$(Q)tag=`echo $(TAG) | tr -d "v"` ; \
	grep -q "$$tag" "meson.build" || \
		{ printf "$(CYN)>>> $(RED)$$tag does not match the 'version' found in 'meson.build'. Please update that file.$(END)\n" ; exit 1 ; }
	@printf "$(CYN)>>> $(GRN)Version in meson.build looks fine.$(END)\n"

	$(Q)tag=`echo $(TAG) | tr -d "v"` ;  \
	cat $(METAINFO_FILE) | grep release | grep -v -q $$tag || \
		{ printf "$(CYN)>>> $(RED)Version $$tag not found in the 'releases' section in $(METAINFO_FILE)).$(END)\n" ; exit 1 ; }
	@printf "$(CYN)>>> $(GRN)Version in $(METAINFO_FILE) looks fine.$(END)\n"

##############################
# Packaging
##############################
##@ Packaging and releasing

.PHONY: package
package: $(FLATPAK_BUNDLE)    ## Export the Flatpack bundle

$(FLATPAK_BUNDLE): $(FLATPAK_MANIFEST) $(APP_SRC_MESONS) $(APP_SRC_PY) $(APP_SRC_DATA)
	@rm -rf $(RELEASE_DIR)

	@printf "$(CYN)>>> $(GRN)Building dependencies (in build_dir=$(RELEASE_DIR)...$(END)\n"
	$(Q)flatpak-builder $(FLATPAK_BUILDER_ARGS) $(RELEASE_DIR) $(FLATPAK_MANIFEST)

	@printf "$(CYN)>>> $(GRN)Exporting bundle to repo_dir=$(FLATPAK_REPO_DIR) (build_dir=$(RELEASE_DIR)$(END)\n"
	$(Q)rm -rf $(FLATPAK_REPO_DIR)
	$(Q)flatpak build-export --arch=x86_64 $(FLATPAK_REPO_DIR) $(RELEASE_DIR)

	@printf "$(CYN)>>> $(GRN)Building bundle from repo_dir=$(FLATPAK_REPO_DIR) -> bundle=$(FLATPAK_BUNDLE)$(END)\n"
	$(Q)flatpak build-bundle --arch=x86_64 $(FLATPAK_REPO_DIR) $(FLATPAK_BUNDLE) $(APP_ID) master
	@printf "$(CYN)>>> $(GRN)Bundle available at $(FLATPAK_BUNDLE)$(END)\n"

generate: build-aux/flatpak-pip-generator requirements.txt ## Regenerate some files (ie, pypi-dependencies.json)
	build-aux/flatpak-pip-generator --requirements-file=requirements.txt --output pypi-dependencies

build-aux/flatpak-pip-generator:
	curl -o build-aux/flatpak-pip-generator https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/master/pip/flatpak-pip-generator
	chmod 755 build-aux/flatpak-pip-generator

##############################
# releases
##############################

release:  ## Adds a new TAG and pushes it to the origin for forcing a new release
	$(Q)[ -n "$(TAG)" ] || { printf "$(CYN)>>> $(RED)No TAG provided. Re-run with something like 'make release TAG=v0.0.0'$(END)\n" ; exit 1 ; }

	@printf "$(CYN)>>> $(GRN)Creating new release with TAG=$(TAG)$(END)\n"

	$(Q)[ -z "$(GIT_MODIFIED)" ] || { printf "$(CYN)>>> $(RED)Some modified files detected. Please commit your changes before creating a new release.$(END)\n" ; exit 1 ; }
	$(Q)git co master

	$(Q)git tag | grep -v -q $(TAG) || { printf "$(CYN)>>> $(RED)Version $(TAG) already found in the list of previous tags (last tag=$(GIT_TAG_LATEST)).$(END)\n" ; exit 1 ; }
	$(Q)make check-version

	@printf "$(CYN)>>> $(GRN)Tag $(TAG) looks fine.$(END)\n"

	@printf "$(CYN)>>> $(GRN)Adding new TAG=$(TAG$)$(END)\n"
	$(Q)git tag -d $(TAG) 2>/dev/null || /bin/true
	$(Q)git tag -a $(TAG) -m "New version $(TAG)" || { printf "$(CYN)>>> $(RED)Failed to add TAG=$(TAG) $(END)\n" ; exit 1 ; }

	@printf "$(CYN)>>> $(GRN)Pushing tags $(TAG$)$(END)\n"
	$(Q)git push || { printf "$(CYN)>>> $(RED)Failed to push new tag $(TAG) to origin$(END)\n" ; exit 1 ; }

##############################
# Flathub
##############################
##@ Flathub packages

# other flatpak stuff

flathub-pull: ## Pull changes from the Flathub repository to the submodule
	@printf "$(CYN)>>> $(GRN)Pulling changes in 'flathub' submodule$(END)\n"
	$(Q)git submodule update --remote --merge -- $(FLATHUB_DIR)
	@printf "$(CYN)>>> $(GRN)Done$(END)\n"

flathub-update: pypi-dependencies.json  ## Update the contents of the Flatub submodule
	$(Q)[ -d "$(FLATHUB_DIR)" ] || { printf "$(CYN)>>> $(RED)No $(FLATHUB_DIR) directory$(END)\n" ; exit 1 ; }

	@printf "$(CYN)>>> $(GRN)Copying pypi dependencies$(END)\n"
	$(Q)cp -f pypi-dependencies.json $(FLATHUB_DIR)/

	@printf "$(CYN)>>> $(GRN)Copying manifest$(END)\n"
	$(Q)rm -f $(FLATHUB_DIR)/$(FLATPAK_MANIFEST)
	$(Q)cp -f $(FLATPAK_MANIFEST) $(FLATHUB_DIR)/

	@printf "$(CYN)>>> $(GRN)Patching manifest$(END)\n"
	$(Q)cd $(FLATHUB_DIR) && \
		cat $(FLATHUB_PATCH) | sed -e 's|@TAG@|$(GIT_TAG_LATEST)|g' | patch -p0

##############################
# CI
##############################

ci/setup:
	@printf "$(CYN)>>> $(GRN)Installing flatpak utils...$(END)\n"
	sudo add-apt-repository ppa:alexlarsson/flatpak -y
	sudo apt-get update -q
	sudo apt-get install -y flatpak flatpak-builder elfutils

	make deps

	@printf "$(CYN)>>> $(GRN)Installing pep8...$(END)\n"
	sudo apt-get -y install python3-pip
	sudo pip3 install pycodestyle

ci/check: TAG=$(GIT_TAG_LATEST)
ci/check: check-version check

ci/build: build

ci/release: package
