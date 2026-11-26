PAK_VERSION := $(shell awk '/^Version:/ {print $$2}' ../control)

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PerAppKeyboardPrefs

PerAppKeyboardPrefs_FILES = PAKRootListController.m PAKAppListController.m PAKAppKeyboardController.m ../PAKLog.m
PerAppKeyboardPrefs_FRAMEWORKS = UIKit
PerAppKeyboardPrefs_PRIVATE_FRAMEWORKS = Preferences
PerAppKeyboardPrefs_INSTALL_PATH = /Library/PreferenceBundles
PerAppKeyboardPrefs_CFLAGS = -fobjc-arc -DPAK_VERSION=\"$(PAK_VERSION)\"

include $(THEOS_MAKE_PATH)/bundle.mk
