
# This is a GNU Make Makefile
# Written for GNU Make 3.82
# (c) 2013 Markus Dangl <sky@q1cc.net>
# Licensed under the GPL (However you got your hands on this source file)

###################################################################################################
# Usage (once customized):
# 1. Create the initial "Makefile":
#       > ...shell$ make -f Makefile.make Makefile
#	# The Makefile will automatically be updated in the future.
# 2. Build the application or a specific file:
#       > ...shell$ make
#       > ...shell$ make specific-file
# 3. Clean up
#	# To clean up intermediate files
#       > ...shell$ make clean
#	# To clean up all generated files (e.g. before RCS checkin or src distribution)
#       > ...shell$ make distclean

###################################################################################################
# Configuration of installable debian image
#
#

ARCH := armhf
RELEASE := jessie
VARIANT := minbase
MIRROR := http://ftp2.de.debian.org/debian
IMAGE_SIZE_MB := 512
IMAGE_SIZE_BYTES := $(shell expr ${IMAGE_SIZE_MB} \* 1024 \* 1024)	# TODO make can calc, right?

export ARCH RELEASE VARIANT MIRROR IMAGE_SIZE_MB IMAGE_SIZE_BYTES

SUDO := $(shell which sudo) -E
export SUDO

###################################################################################################

# Files
SOURCE_DIR = .
# Warning: Target and build directory get removed by clean & co
TARGET_DIR = target
BUILD_DIR = build
CACHE_DIR = cache
MARKER = $(BUILD_DIR)/marker

# Targets
DEBDROID = $(BUILD_DIR)/debdroid
DEBDROID_TARBALL = $(TARGET_DIR)/debdroid.tar.gz
FSIMAGE=$(BUILD_DIR)/fsimage.bin
FULL_IMAGE=$(TARGET_DIR)/fsimage.bin
TARGETS = $(DEBDROID_TARBALL) $(FULL_IMAGE)
ALL_TARGETS = $(TARGETS)

SCRIPT = $(shell readlink -f ./helper.sh)

# User
REALUSER = $(shell id -un)
export REALUSER

# Strings
INFO_CLEAN = $(info )$(info Cleaning up...)$(info )
INFO_MAKEFILE = $(info )$(info Updating Makefile...)

INFO_BUILD = $(info Building $(1)...)

# OS detection
UNAME = $(shell uname)
#$(info OS: $(OS) $(UNAME))
ifneq (,$(findstring CYGWIN,$(UNAME)))
    OSMODE=cygwin
    FU_SEP=/
    RM=rm -rf
	RMDIR=rmdir
    CP=cp
	MV=mv
	LN=ln -s
    MKDIR=mkdir -p
    SHARED_LIBRARY_SUFFIX=.dll
else ifeq ($(OS),Windows_NT)
	# THIS SCRIPT WILL NEVER RUN UNDER WINDOWS U KNOW
    OSMODE=windows
    FU_SEP=\\
    RM=rd /S /Q
	RMDIR=rd
    CP=copy >nul
	MV=?? # TODO
	LN=?? # WONT EVER WORK
    MKDIR=mkdir 2>nul
    SHARED_LIBRARY_SUFFIX=.dll
else
    OSMODE=unix
    FU_SEP=/
    RM=rm -rf
	RMDIR=rmdir
    CP=cp
	MV=mv
	LN=ln -s
    MKDIR=mkdir -p
    SHARED_LIBRARY_SUFFIX=.so
endif
#$(info Using $(OSMODE) style commands and paths.)

.PHONY: default clean-rooted clean dist-clean distclean all info checks
.PRECIOUS: $(DEBDROID) $(DEBDROID).tar.gz

default: all
#default: info

clean-rooted: ; $(INFO_CLEAN)
	-$(SUDO) $(RM) $(DEBDROID)
	# Just to be sure
	-$(SUDO) $(RM) $(DEBDROID).tar.gz

clean: clean-rooted ; $(INFO_CLEAN)
	-$(RM) $(BUILD_DIR)

distclean dist-clean: clean; $(INFO_CLEAN)
	-$(RM) $(TARGET_DIR)

all: $(ALL_TARGETS)

$(BUILD_DIR) $(TARGET_DIR) $(CACHE_DIR) $(MARKER):
	$(MKDIR) $@

$(MARKER): | $(TARGET)

info: checks
	$(SCRIPT) info

checks:
	$(SCRIPT) checks

###################################################################################################

#$(BUILD_DIR)/%.temp: $(SOURCE_DIR)/%.srcfile $(BUILD_DIR)
#	@executable-preprocess-source --some-parameter $< > $@

#$(TARGET_DIR)/%.bin: $(BUILD_DIR)/%.temp $(TARGET_DIR) ; $(call INFO_BUILD,$(notdir $@))
#	@executable-compile-binary --some-parameter -o $@ $<

# Pre-download debootstrap packages

CACHEFILE = $(CACHE_DIR)/debootstrap-$(RELEASE)-$(ARCH).tgz
$(CACHEFILE): | $(CACHE_DIR)
	$(SCRIPT) bootstrap-download $@

$(DEBDROID): $(CACHEFILE) | $(BUILD_DIR) checks
	-$(SUDO) $(RM) $(DEBDROID)
	$(SCRIPT) bootstrap $@ $<

$(DEBDROID).tar.gz: $(DEBDROID) ; $(call INFO_BUILD,$(notdir $@))
	-$(SUDO) $(RM) $(DEBDROID).tar.gz
	$(SCRIPT) tarball $< $@

$(DEBDROID_TARBALL): $(DEBDROID).tar.gz | $(TARGET_DIR) ; $(call INFO_BUILD,$(notdir $@))
	$(MV) $< $@
	$(LN) ../$@ $<

$(FSIMAGE): $(DEBDROID) | $(BUILD_DIR)
	-rm $@
	dd if=/dev/zero bs=1M count=${IMAGE_SIZE_MB} | pv -s ${IMAGE_SIZE_BYTES} > $@
	$(SCRIPT) format-fsimage "$@"

$(FULL_IMAGE): $(FSIMAGE) $(DEBDROID) | $(TARGET_DIR)
	-rm $@
	$(SCRIPT) loop-mount "$<" "$(BUILD_DIR)/mnt"
	$(SCRIPT) copy-content "$(DEBDROID)" "$(BUILD_DIR)/mnt"
	
	@# TODO should be optional
	@echo "--------------------------------------------------------------------------------"
	@echo "Pausing script here to allow for custom modifications."
	@echo "The current filesystem is mounted at: $(BUILD_DIR)/mnt"
	@echo "Press return to continue."
	@read DUMMY
	@echo "--------------------------------------------------------------------------------"
	
	$(SCRIPT) umount "$(BUILD_DIR)/mnt"
	$(RMDIR) "$(BUILD_DIR)/mnt"
	@# Linux _should_ destroy the loopback device automatically
	$(MV) $< $@
	$(LN) ../$@ $<

###################################################################################################

Makefile: Makefile.make ; $(INFO_MAKEFILE)
	@$(CP) $< $@

