# Dockershelf Python packaging pipeline (Debian-native)
#
# Run from python-pipeline/ inside the deadsnakes-pipeline workspace.
# Sibling py3.* repos live in the parent directory (..).
#
# Quick start:
#   cp config.env.example config.env
#   make bootstrap
#   make build-builder-images
#   make materialize PY=3.13 DIST=trixie
#   make build PY=3.13
#   make publish DIST=trixie

SHELL := bash -euo pipefail
PIPELINE := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
WORKSPACE := $(abspath $(PIPELINE)/..)
DIST_DIR := $(PIPELINE)/dist

ifneq (,$(wildcard $(PIPELINE)/config.env))
include $(PIPELINE)/config.env
endif
export DOCKERSHELF_BUILDER_IMAGE ?= dockershelf-python-builder
export DOCKERSHELF_TOOLS_IMAGE ?= dockershelf-python-builder/tools
ifdef DEBFULLNAME
export DEBFULLNAME
endif
ifdef DEBEMAIL
export DEBEMAIL
endif
export DOCKERSHELF_SUITES ?= trixie unstable
export DOCKERSHELF_REFERENCE_PY ?= 3.13
export DOCKERSHELF_DEPLOY_HOST ?= apt.luisalejandro.org
export DOCKERSHELF_DEPLOY_USER ?= deploy
export DOCKERSHELF_DEPLOY_DIR ?= /var/www/debian
export DOCKERSHELF_DEPLOY_INCOMING ?= /var/www/debian/incoming
export DOCKERSHELF_APT_URL ?= https://apt.luisalejandro.org/dockershelf
export DOCKERSHELF_GITHUB_ORG ?= Dockershelf

PY_VERSIONS := 3.10 3.11 3.12 3.13 3.14

.PHONY: all bootstrap clone-py-repos build-tools-image generate-dockerfiles build-builder-images \
	materialize build publish list-dists help

all: help

help:
	@echo "Targets:"
	@echo "  bootstrap                 Clone py3.* repos into workspace parent"
	@echo "  build-tools-image         Build dockershelf-python-builder/tools (gbp, dch, …)"
	@echo "  generate-dockerfiles      Generate Dockerfile.{suite} from debian/control"
	@echo "  build-builder-images      Build dockershelf-python-builder/* (Debian base)"
	@echo "  materialize PY=3.13 DIST=trixie"
	@echo "  build PY=3.13             Build binary .deb packages (unsigned)"
	@echo "  publish DIST=trixie       Rsync dist/*.deb to DO droplet + reprepro import"
	@echo "  list-dists                Show Debian suites per py repo"
	@echo ""
	@echo "Config: copy config.env.example to config.env"

bootstrap: clone-py-repos
	@echo "Bootstrap complete."

clone-py-repos:
	@for v in $(PY_VERSIONS); do \
		target="$(WORKSPACE)/py$$v"; \
		if [ ! -d "$$target/.git" ]; then \
			echo "Cloning py$$v..."; \
			git clone --depth 1 "https://github.com/$(DOCKERSHELF_GITHUB_ORG)/py$$v.git" "$$target"; \
		else \
			echo "py$$v already cloned"; \
		fi; \
	done

build-tools-image:
	@echo "Building $(DOCKERSHELF_TOOLS_IMAGE)"
	@docker build -t "$(DOCKERSHELF_TOOLS_IMAGE)" \
		-f "$(PIPELINE)/dockerfiles/Dockerfile.tools" "$(PIPELINE)/dockerfiles"

generate-dockerfiles: bootstrap
	@mkdir -p "$(PIPELINE)/dockerfiles"
	@REF="$(WORKSPACE)/py$(DOCKERSHELF_REFERENCE_PY)/debiandirs"; \
	for suite in $(DOCKERSHELF_SUITES); do \
		control="$$REF/$$suite/control"; \
		if [ ! -f "$$control" ]; then \
			echo "ERROR: missing $$control"; \
			exit 1; \
		fi; \
		echo "Generating Dockerfile.$$suite"; \
		"$(PIPELINE)/make-new-image" --codename "$$suite" "$$control" \
			> "$(PIPELINE)/dockerfiles/Dockerfile.$$suite"; \
	done

build-builder-images: generate-dockerfiles build-tools-image
	@for suite in $(DOCKERSHELF_SUITES); do \
		df="$(PIPELINE)/dockerfiles/Dockerfile.$$suite"; \
		if [ ! -f "$$df" ]; then \
			echo "ERROR: missing $$df (run make generate-dockerfiles)"; \
			exit 1; \
		fi; \
		echo "Building $(DOCKERSHELF_BUILDER_IMAGE)/$$suite"; \
		docker build -t "$(DOCKERSHELF_BUILDER_IMAGE)/$$suite" -f "$$df" "$(PIPELINE)/dockerfiles"; \
	done

list-dists:
	@for v in $(PY_VERSIONS); do \
		if [ -d "$(WORKSPACE)/py$$v/changelogs/mainline" ]; then \
			suites=""; \
			for s in $(DOCKERSHELF_SUITES); do \
				if [ -f "$(WORKSPACE)/py$$v/changelogs/mainline/$$s" ]; then \
					suites="$$suites $$s"; \
				fi; \
			done; \
			echo "py$$v:$$suites"; \
		fi; \
	done

materialize: bootstrap build-tools-image
	@test -n "$(PY)" || (echo "PY required, e.g. make materialize PY=3.13 DIST=trixie" && exit 1)
	@test -n "$(DIST)" || (echo "DIST required, e.g. DIST=trixie" && exit 1)
	@case " $(DOCKERSHELF_SUITES) " in \
		*" $(DIST) "*) ;; \
		*) echo "DIST must be one of: $(DOCKERSHELF_SUITES)"; exit 1;; \
	esac
	@cd "$(WORKSPACE)/py$(PY)" && ../python-pipeline/meta-gbp materialize "$(DIST)"

build: bootstrap build-tools-image
	@test -n "$(PY)" || (echo "PY required" && exit 1)
	@mkdir -p "$(DIST_DIR)"
	@cd "$(WORKSPACE)/py$(PY)" && ../python-pipeline/meta-gbp build
	@echo "Packages written to $(DIST_DIR)/"

publish:
	@test -n "$(DIST)" || (echo "DIST required, e.g. make publish DIST=trixie" && exit 1)
	@shopt -s nullglob; debs=("$(DIST_DIR)"/*.deb); \
	if [ "$${#debs[@]}" -eq 0 ]; then \
		echo "No .deb files in $(DIST_DIR)/ — run make build first"; \
		exit 1; \
	fi; \
	echo "Publishing $${#debs[@]} package(s) to $(DOCKERSHELF_DEPLOY_USER)@$(DOCKERSHELF_DEPLOY_HOST):$(DOCKERSHELF_DEPLOY_INCOMING)/"; \
	rsync -av --progress "$${debs[@]}" \
		"$(DOCKERSHELF_DEPLOY_USER)@$(DOCKERSHELF_DEPLOY_HOST):$(DOCKERSHELF_DEPLOY_INCOMING)/"; \
	ssh "$(DOCKERSHELF_DEPLOY_USER)@$(DOCKERSHELF_DEPLOY_HOST)" \
		"REPO_ROOT=$(DOCKERSHELF_DEPLOY_DIR) INCOMING=$(DOCKERSHELF_DEPLOY_INCOMING) \
		/usr/local/bin/dockershelf-import-incoming $(DIST) || \
		bash -s $(DIST)" < "$(PIPELINE)/debian-repo-setup/import-incoming.sh"; \
	echo "Published to $(DOCKERSHELF_APT_URL) ($(DIST))"
