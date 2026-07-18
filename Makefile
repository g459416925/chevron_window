THEOS ?= /opt/theos
TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChevronV3 ChevronV3VideoBridge

ChevronV3_FILES = Tweak.x
ChevronV3_CFLAGS = -fobjc-arc
ChevronV3_ARCHS = arm64 arm64e
ChevronV3_FRAMEWORKS = UIKit CoreGraphics CoreMotion QuartzCore

ChevronV3VideoBridge_FILES = CV3VideoBridge.x
ChevronV3VideoBridge_CFLAGS = -fobjc-arc
ChevronV3VideoBridge_ARCHS = arm64 arm64e
ChevronV3VideoBridge_FRAMEWORKS = UIKit AVFAudio

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = ChevronV3Prefs
ChevronV3Prefs_FILES = ChevronV3Prefs/CV3RootListController.m
ChevronV3Prefs_CFLAGS = -fobjc-arc
ChevronV3Prefs_ARCHS = arm64 arm64e
ChevronV3Prefs_FRAMEWORKS = UIKit
ChevronV3Prefs_PRIVATE_FRAMEWORKS = Preferences
ChevronV3Prefs_INSTALL_PATH = /Library/PreferenceBundles
ChevronV3Prefs_RESOURCE_DIRS = ChevronV3Prefs/Resources

include $(THEOS_MAKE_PATH)/bundle.mk
