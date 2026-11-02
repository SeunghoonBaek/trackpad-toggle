.DEFAULT_GOAL := build

APP_NAME := Trackpad Toggle.app
INSTALL_DIR ?= /Applications

.PHONY: build install

build:
	bash build.sh

install: build
	ditto "$(APP_NAME)" "$(INSTALL_DIR)/$(APP_NAME)"
	codesign --verify --strict "$(INSTALL_DIR)/$(APP_NAME)"
	@printf 'Installed: %s\n' "$(INSTALL_DIR)/$(APP_NAME)"
