THEOS ?= /opt/theos
TARGET := iphone:clang:latest:14.0
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
