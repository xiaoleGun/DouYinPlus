# 插件：显示编译成功，显示的信息
PACKAGE_IDENTIFIER = com.xiaolegun.douyinplus
PACKAGE_NAME = DouYinPlus
PACKAGE_VERSION = 0.1
PACKAGE_ARCHITECTURE = iphoneos-arm64
PACKAGE_REVISION = 1
PACKAGE_SECTION = Tweaks
PACKAGE_DEPENDS = firmware (>= 15.0), mobilesubstrate
PACKAGE_DESCRIPTION = DouYinPlus by xiaoleGun

# 插件：编译时，引用的信息
define Package/$(PACKAGE_IDENTIFIER)
  Package: com.xiaolegun.douyinplus
  Name: DouYinPlus
  Version: 0.1
  Architecture: iphoneos-arm64
  Author: xiaoleGun
  Section: Tweaks
  Depends: firmware (>= 15.0), mobilesubstrate
endef

# 直接输出到根路径
export THEOS_PACKAGE_DIR = $(CURDIR)

# TARGET
ARCHS = arm64
TARGET = iphone:clang:latest:15.0
# 旧命令行参数兼容；新命令统一使用 DYPLUS_RELEASE。
ifdef DYYY_RELEASE
DYPLUS_RELEASE ?= $(DYYY_RELEASE)
endif
DYPLUS_RELEASE ?= 1

# 严格 Logos 语法；编译警告保持可见，由 audit-strict 升级为错误。
export DEBUG = 0
export THEOS_STRICT_LOGOS = 1
export ERROR_ON_WARNINGS = 0
export LOGOS_DEFAULT_GENERATOR = internal

# Rootless 插件配置
export THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_INSTALL_PREFIX = /var/jb

# 目标进程
INSTALL_TARGET_PROCESSES = Aweme

# 引入 Theos 的通用设置
include $(THEOS)/makefiles/common.mk

# 插件名称
TWEAK_NAME = DYPlus

# 模块源文件清单保持原有 Hook 注册顺序。
include $(THEOS_PROJECT_DIR)/Build/DYPlusModules.mk
$(TWEAK_NAME)_FILES = $(DYPLUS_SOURCE_FILES)

# ===== 发布版 / 调试版开关 =====
# make / make DYPLUS_RELEASE=1  发布版（默认）：主功能 + 一键自检；大小见审计实测
# make DYPLUS_RELEASE=0  调试版：另含 FLEX、Capstone 与逆向助手，不建议日常使用
#   排除 FLEX 全部 / Capstone / 逆向助手 Decrypt / flex_fishhook；长按面板 FLEX 菜单与设置页调试入口随之隐藏
ifneq ($(DYPLUS_RELEASE),1)
# 调试版：添加 FLEX 源文件
FLEX_FILES := $(shell find Vendor/FLEX -name '*.m' -o -name '*.mm' | grep -v 'Vendor/FLEX/x/retdec' | grep -v 'Vendor/FLEX/x/capstone' | grep -v 'UCDecompiler')
$(TWEAK_NAME)_FILES += $(FLEX_FILES) Vendor/FLEX/flex_fishhook.c

# Capstone 源文件（使用 FLEX 自带的 iOS 版本，用于反汇编）
CAPSTONE_CORE := $(shell find Vendor/FLEX/x/capstone -maxdepth 1 -name "*.c")
CAPSTONE_ARM := $(shell find Vendor/FLEX/x/capstone/arch/ARM -name "*.c")
CAPSTONE_ARM64 := $(shell find Vendor/FLEX/x/capstone/arch/AArch64 -name "*.c")
$(TWEAK_NAME)_FILES += $(CAPSTONE_CORE) $(CAPSTONE_ARM) $(CAPSTONE_ARM64)
endif

# 编译标志
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
# 发布版宏（必须在基础 CFLAGS 赋值之后追加，否则被覆盖）
ifeq ($(DYPLUS_RELEASE),1)
$(TWEAK_NAME)_CFLAGS += -DDYPLUS_RELEASE_BUILD=1
# 发布包优化体积，保留 Objective-C 元数据和所有运行时 Hook。
$(TWEAK_NAME)_CFLAGS += -Os
$(TWEAK_NAME)_LDFLAGS += -Wl,-dead_strip
endif
# 解决class_ro_t指针签名警告
$(TWEAK_NAME)_CFLAGS += -Wno-deprecated-declarations -Wno-sign-compare -Wno-pointer-sign
# 统一启用class_ro_t指针签名，避免混合编译警告
$(TWEAK_NAME)_CFLAGS += -fobjc-runtime=ios-15.0
# Capstone 架构支持
$(TWEAK_NAME)_CFLAGS += -DCAPSTONE_HAS_ARM -DCAPSTONE_HAS_AARCH64 -DCAPSTONE_USE_SYS_DYN_MEM

# 保留内部生成器选项
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

# 框架
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation Photos CoreGraphics QuartzCore ImageIO CoreLocation AudioToolbox AVFAudio AVFoundation CoreMedia MediaToolbox Accelerate
ifneq ($(DYPLUS_RELEASE),1)
$(TWEAK_NAME)_FRAMEWORKS += Security Metal MetalKit CoreImage SwiftUI Combine
endif
# 链接器标志，解决class_ro_t指针签名警告
$(TWEAK_NAME)_LDFLAGS += -Xlinker -no_adhoc_codesign -Xlinker -objc_abi_version -Xlinker 2
# 统一class_ro_t指针签名设置，解决链接警告
$(TWEAK_NAME)_LDFLAGS += -Xlinker -no_warn_duplicate_libraries
# FLEX 库和头文件路径
$(TWEAK_NAME)_LIBRARIES = 
$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)
$(TWEAK_NAME)_CFLAGS += -I$(THEOS)/include
$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)/Vendor/FLEX
$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)/Sources/DYPlus
$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)/Vendor
$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)/Vendor/FLEX/x/capstone/include
$(TWEAK_NAME)_CCFLAGS = -std=c++17 -fno-rtti -fno-modules
$(TWEAK_NAME)_CCFLAGS += -I$(THEOS_PROJECT_DIR)/Vendor/FLEX/x/capstone/include

# 仅保留已知私有类 category/protocol 声明所需的定向抑制。
$(TWEAK_NAME)_CFLAGS += -Wno-incomplete-implementation
$(TWEAK_NAME)_CFLAGS += -Wno-protocol
$(TWEAK_NAME)_CFLAGS += -Wno-objc-protocol-method-implementation

# 预处理变量
$(TWEAK_NAME)_CFLAGS += -DDOKIT_FULL_BUILD=1
$(TWEAK_NAME)_CFLAGS += -DDORAEMON_FULL_BUILD=1

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: audit-hooks audit-risks audit-strict
audit-hooks:
	@python3 scripts/check_dyplus_hooks.py

audit-risks:
	@python3 scripts/check_dyplus_project.py

audit-strict: ERROR_ON_WARNINGS = 1
audit-strict: audit-hooks audit-risks all
