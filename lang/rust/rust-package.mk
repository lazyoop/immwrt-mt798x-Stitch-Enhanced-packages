# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 Luca Barbato and Donald Hoskins

# Variables (all optional) to be set in package Makefiles:
#
# RUST_PKG_FEATURES - list of options, default empty
#
#   Space or comma separated list of features to activate
#
#   e.g. RUST_PKG_FEATURES:=enable-foo,with-bar

ifeq ($(origin RUST_INCLUDE_DIR),undefined)
  RUST_INCLUDE_DIR:=$(dir $(lastword $(MAKEFILE_LIST)))
endif
include $(RUST_INCLUDE_DIR)/rust-values.mk

# $(1) path to the package (optional)
# $(2) additional arguments to cargo (optional)
define Build/Compile/Cargo
	( \
		cd $(PKG_BUILD_DIR) ; \
		CARGO_HOME=$(CARGO_HOME) \
		CARGO_PROFILE_RELEASE_OPT_LEVEL=s \
		CARGO_TARGET_$(subst -,_,$(call toupper,$(RUSTC_TARGET_ARCH)))_LINKER=$(TARGET_CC_NOCACHE) \
		TARGET_CFLAGS="$(TARGET_CFLAGS) $(RUSTC_CFLAGS)" \
		TARGET_CC=$(TARGET_CC_NOCACHE) \
		CC=$(HOSTCC_NOCACHE) \
		RUSTFLAGS="$(CARGO_RUSTFLAGS)" \
		$(CARGO_VARS) \
		cargo install -v \
			--profile $(CARGO_PKG_PROFILE) \
			--target $(RUSTC_TARGET_ARCH) \
			$(if $(strip $(RUST_PKG_FEATURES)),--features "$(strip $(RUST_PKG_FEATURES))") \
			--root $(PKG_INSTALL_DIR) \
			--path "$(if $(strip $(1)),$(strip $(1)),.)" \
			$(2) ; \
	)
endef

define RustBinPackage
  ifndef Package/$(1)/install
    define Package/$(1)/install
	$$(INSTALL_DIR) $$(1)/usr/bin/
	$$(INSTALL_BIN) $$(PKG_INSTALL_DIR)/bin/* $$(1)/usr/bin/
    endef
  endif
endef

Build/Compile=$(call Build/Compile/Cargo)
