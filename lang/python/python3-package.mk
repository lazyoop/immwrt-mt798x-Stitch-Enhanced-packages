#
# Copyright (C) 2007-2016 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

# Note: include this file after `include $(TOPDIR)/rules.mk in your package Makefile

python3_mk_path:=$(dir $(lastword $(MAKEFILE_LIST)))
include $(python3_mk_path)python3-host.mk

PYTHON3_DIR:=$(STAGING_DIR)/usr
PYTHON3_INC_DIR:=$(PYTHON3_DIR)/include/python$(PYTHON3_VERSION)
PYTHON3_LIB_DIR:=$(PYTHON3_DIR)/lib/python$(PYTHON3_VERSION)

PYTHON3_PKG_DIR:=/usr/lib/python$(PYTHON3_VERSION)/site-packages

PYTHON3:=python$(PYTHON3_VERSION)

PYTHON3PATH:=$(PYTHON3_LIB_DIR):$(STAGING_DIR)/$(PYTHON3_PKG_DIR):$(PKG_INSTALL_DIR)/$(PYTHON3_PKG_DIR)

# These configure args are needed in detection of path to Python header files
# using autotools.
CONFIGURE_ARGS += \
	_python_sysroot="$(STAGING_DIR)" \
	_python_prefix="/usr" \
	_python_exec_prefix="/usr"

PYTHON3_VARS = \
	CC="$(TARGET_CC)" \
	CCSHARED="$(TARGET_CC) $(FPIC)" \
	CXX="$(TARGET_CXX)" \
	LD="$(TARGET_CC)" \
	LDSHARED="$(TARGET_CC) -shared" \
	CFLAGS="$(TARGET_CFLAGS)" \
	CPPFLAGS="$(TARGET_CPPFLAGS) -I$(PYTHON3_INC_DIR)" \
	LDFLAGS="$(TARGET_LDFLAGS) -lpython$(PYTHON3_VERSION)" \
	_PYTHON_HOST_PLATFORM=linux2 \
	__PYVENV_LAUNCHER__="/usr/bin/$(PYTHON3)" \
	PYTHONPATH="$(PYTHON3PATH)" \
	PYTHONDONTWRITEBYTECODE=1 \
	PYTHONOPTIMIZE="" \
	_python_sysroot="$(STAGING_DIR)" \
	_python_prefix="/usr" \
	_python_exec_prefix="/usr"

# $(1) => directory of python script
# $(2) => python script and its arguments
# $(3) => additional variables
define Python3/Run
	cd "$(if $(strip $(1)),$(strip $(1)),.)" && \
	$(PYTHON3_VARS) \
	$(3) \
	$(HOST_PYTHON3_BIN) $(2)
endef

# $(1) => build subdir
# $(2) => additional arguments to setup.py
# $(3) => additional variables
define Python3/ModSetup
	$(INSTALL_DIR) $(PKG_INSTALL_DIR)/$(PYTHON3_PKG_DIR)
	$(call Python3/Run, \
		$(PKG_BUILD_DIR)/$(strip $(1)), \
		setup.py $(2), \
		$(3))
endef

define Python3/FixShebang
	$(SED) "1"'!'"b;s,^#"'!'".*python.*,#"'!'"/usr/bin/python3," -i --follow-symlinks $(1)
endef

# default max recursion is 10
PYTHON3_COMPILEALL_MAX_RECURSION_LEVEL:=20

# $(1) => directory of python source files to compile
#
# XXX [So that you won't goof as I did]
# Note: Yes, I tried to use the -O & -OO flags here.
#       However the generated byte-codes were not portable.
#       So, we just stuck to un-optimized byte-codes,
#       which is still way better/faster than running
#       Python sources all the time.
#
# Setting a fixed hash seed value is less secure than using
# random seed values, but is necessary for reproducible builds
# (for now).
#
# Should revisit this when https://bugs.python.org/issue37596
# (and other related reproducibility issues) are fixed.
define Python3/CompileAll
	$(call Python3/Run,, \
		-m compileall -r "$(PYTHON3_COMPILEALL_MAX_RECURSION_LEVEL)" -b -d '/' $(1),
		$(if $(SOURCE_DATE_EPOCH),PYTHONHASHSEED="$(SOURCE_DATE_EPOCH)")
	)
endef

# $(1) => target directory
define Python3/DeleteSourceFiles
	$(FIND) $(1) -type f -name '*.py' -delete
endef

# $(1) => target directory
define Python3/DeleteNonSourceFiles
	$(FIND) $(1) -not -type d -not -name '*.py' -delete
endef

# $(1) => target directory
define Python3/DeleteEmptyDirs
	$(FIND) $(1) -mindepth 1 -empty -type d -not -path '$(1)/CONTROL' -not -path '$(1)/CONTROL/*' -delete
endef


# Py3Package

define Py3Package/filespec/Default
+|$(PYTHON3_PKG_DIR)
endef

# $(1) => package name
# $(2) => src directory
# $(3) => dest directory
define Py3Package/ProcessFilespec
	$(eval $(call shexport,Py3Package/$(1)/filespec))
	$(SHELL) $(python3_mk_path)python-package-install.sh \
		"$(2)" "$(3)" "$$$$$(call shvar,Py3Package/$(1)/filespec)"
endef

define Py3Package
  define Package/$(1)-src
    $(call Package/$(1))
    DEPENDS:=
    CONFLICTS:=
    PROVIDES:=
    EXTRA_DEPENDS:=
    TITLE+= (sources)
    USERID:=
    MENU:=
  endef

  define Package/$(1)-src/description
    $$(call Package/$(1)/description)

    This package contains the Python source files for $(1).
  endef

  define Package/$(1)-src/config
    depends on PACKAGE_$(1)
  endef

  # Add default PyPackage filespec none defined
  ifeq ($(origin Py3Package/$(1)/filespec),undefined)
    Py3Package/$(1)/filespec=$$(Py3Package/filespec/Default)
  endif

  ifndef Py3Package/$(1)/install
    define Py3Package/$(1)/install
	if [ -d $(PKG_INSTALL_DIR)/usr/bin ]; then \
		$(INSTALL_DIR) $$(1)/usr/bin ; \
		$(CP) $(PKG_INSTALL_DIR)/usr/bin/* $$(1)/usr/bin/ ; \
	fi
    endef
  endif

  ifndef Package/$(1)/install
    define Package/$(1)/install
	$$(call Py3Package/$(1)/install,$$(1))
	$$(call Py3Package/ProcessFilespec,$(1),$(PKG_INSTALL_DIR),$$(1))
	$(FIND) $$(1) -name '*.exe' -delete
	$$(call Python3/CompileAll,$$(1))
	$$(call Python3/DeleteSourceFiles,$$(1))
	$$(call Python3/DeleteEmptyDirs,$$(1))
	if [ -d "$$(1)/usr/bin" ]; then \
		$$(call Python3/FixShebang,$$(1)/usr/bin/*) ; \
	fi
    endef

    define Package/$(1)-src/install
	$$(call Py3Package/$(1)/install,$$(1))
	$$(call Py3Package/ProcessFilespec,$(1),$(PKG_INSTALL_DIR),$$(1))
	$$(call Python3/DeleteNonSourceFiles,$$(1))
	$$(call Python3/DeleteEmptyDirs,$$(1))
    endef
  endif # Package/$(1)/install
endef


# Py3Build

PYTHON3_PKG_SETUP_DIR ?=
PYTHON3_PKG_SETUP_GLOBAL_ARGS ?=
PYTHON3_PKG_SETUP_ARGS ?= --single-version-externally-managed
PYTHON3_PKG_SETUP_VARS ?=

define Py3Build/FindStdlibDepends
	$(SHELL) $(python3_mk_path)python3-find-stdlib-depends.sh -n "$(PKG_NAME)" "$(PKG_BUILD_DIR)"
endef

define Py3Build/Compile/Default
	$(if $(HOST_PYTHON3_PACKAGE_BUILD_DEPENDS),
		$(call HostPython3/PipInstall,$(HOST_PYTHON3_PACKAGE_BUILD_DEPENDS))
	)
	$(call Python3/ModSetup, \
		$(PYTHON3_PKG_SETUP_DIR), \
		$(PYTHON3_PKG_SETUP_GLOBAL_ARGS) \
		install --prefix="/usr" --root="$(PKG_INSTALL_DIR)" \
		$(PYTHON3_PKG_SETUP_ARGS), \
		$(PYTHON3_PKG_SETUP_VARS) \
	)
endef

Py3Build/Configure=$(Py3Build/Configure/Default)
Py3Build/Compile=$(Py3Build/Compile/Default)

PYTHON3_PKG_BUILD ?= 1

ifeq ($(strip $(PYTHON3_PKG_BUILD)),1)
  ifeq ($(PY3),stdlib)
    Hooks/Configure/Post+=Py3Build/FindStdlibDepends
  endif
  Build/Compile=$(Py3Build/Compile)
endif
