TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PerAppKeyboard

PerAppKeyboard_FILES = Tweak.x
PerAppKeyboard_CFLAGS = -fobjc-arc

SUBPROJECTS = PerAppKeyboardPrefs PerAppKeyboardCC

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# A restrictive umask on the build host would otherwise ship files as 600 / dirs as 700, and
# Preferences / PreferenceLoader run as `mobile`, so the pane would fail to load.
before-package::
	@find "$(THEOS_STAGING_DIR)" -type d -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -exec chmod 644 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -name '*.dylib' -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f \( -path '*/PerAppKeyboardPrefs.bundle/PerAppKeyboardPrefs' -o -path '*/PerAppKeyboardCC.bundle/PerAppKeyboardCC' \) -exec chmod 755 {} +
