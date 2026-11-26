TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PerAppKeyboard

PerAppKeyboard_FILES = Tweak.x PAKSwitcher.m PAKLifecycle.m PAKLog.m
PerAppKeyboard_CFLAGS = -fobjc-arc

SUBPROJECTS = PerAppKeyboardPrefs PerAppKeyboardCC

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk