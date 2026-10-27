THEOS ?= /opt/theos
TARGET := iphone:clang:16.5:14.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iconprobe
iconprobe_FILES = iconprobe.x
iconprobe_CFLAGS = -fobjc-arc
iconprobe_ARCHS = arm64 arm64e
iconprobe_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
