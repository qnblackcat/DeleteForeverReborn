TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = MobileSlideShow Camera

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeleteForeverReborn
DeleteForeverReborn_FILES = iOS15_16.x iOS17.x Shared.m
DeleteForeverReborn_CFLAGS = -fobjc-arc
DeleteForeverReborn_FRAMEWORKS = UIKit Photos

include $(THEOS_MAKE_PATH)/tweak.mk
