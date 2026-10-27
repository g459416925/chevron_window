# ChevronV3（com.xu.chevronv3）

> 原项目路径 `/Users/xu/ChevronLauncher` 已归置到本工作区。
> 项目区：`ChevronV3/`；源码唯一位置：`src/`；构建配置：根目录 `Makefile`/`control`/`layout`；产物：`dist/`。

## 结构

```text
ChevronV3/
├── src/                    Tweak.x、CV3*.h/.inc/.x、ChevronV3*.plist、ChevronV3Prefs/
├── Makefile / control      Theos 构建配置
├── layout/                 PreferenceLoader 布局
├── dist/                   当前 deb（1.0.18-227+env-fast-1+debug）
├── docs/                   原 README/FEATURE/测试记录
├── data/                   历史构建、证据、备份、工具（项目数据）
└── .git/                   原项目 Git 历史
```

## 构建

```bash
cd ChevronV3
make clean package
```

## 当前设备状态

- 已安装：`com.xu.chevronv3 1.0.18-227+env-fast-1+debug`
- 项目 deb：`dist/com.xu.chevronv3_1.0.18-227+env-fast-1+debug_iphoneos-arm64e.deb`
- 版本一致；deb 已同步到发布仓库 `ios-tweaks/debs/`。
