ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

ARCHS := arm64
INSTALL_TARGET_PROCESSES := YouTubeMusic
TARGET := iphone:clang:16.5:13.0
PACKAGE_VERSION := 2.3.1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME += YTMusicUltimate

YTMusicUltimate_FILES += $(shell find Source -name '*.xm' -o -name '*.x' -o -name '*.m')
YTMusicUltimate_CFLAGS += -fobjc-arc -Wno-deprecated-declarations -DTWEAK_VERSION=$(PACKAGE_VERSION)
YTMusicUltimate_FRAMEWORKS += UIKit Foundation AVFoundation AudioToolbox VideoToolbox
YTMusicUltimate_OBJ_FILES += $(shell find Source/Utils/lib -name '*.a')
YTMusicUltimate_LIBRARIES += bz2 c++ iconv z
ifeq ($(SIDELOADING),1)
YTMusicUltimate_FILES += Sideloading.xm
endif

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
YTMusicUltimate_FILES += libroot/dyn.c
YTMusicUltimate_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk
