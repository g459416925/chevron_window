# ChevronV3（com.xu.chevronv3）

> 原项目路径 `/Users/xu/ChevronLauncher` 已归置到本工作区。
> 项目区：`ChevronV3/`；源码唯一位置：`src/`；构建配置：根目录 `Makefile`/`control`/`layout`；产物：`dist/`。

## 结构

```text
ChevronV3/
├── src/                    Tweak.x、CV3*.h/.inc/.x、ChevronV3Prefs/
├── ChevronV3*.plist        MobileSubstrate 过滤 plist（Theos 要求位于 Makefile 同级根目录）
├── Makefile / control      Theos 构建配置
├── layout/                 PreferenceLoader 布局
├── dist/                   当前 deb
├── docs/                   原 README/FEATURE/测试记录
├── data/                   项目数据（tools 探针）
└── .git/                   原项目 Git 历史
```

## 构建

```bash
cd ChevronV3
make clean package
```

## 当前设备状态

- 已安装：`com.xu.chevronv3 1.0.18-227+env-fast-1+debug`（设备待升级 232）
- 项目 deb：`dist/com.xu.chevronv3_1.0.18-232+code-review-2+debug_iphoneos-arm64e.deb`
- 2026-10-27 深度审阅：去重/死代码清理/漏洞修复，详见 `.workbuddy/memory/2026-10-27.md`
