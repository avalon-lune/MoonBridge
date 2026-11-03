# 构建与运行

## 前提

本项目以 Apple Silicon Mac 为目标，GUI 最低部署目标为 macOS 14。当前实测硬件、系统与工具链见 [验证记录](VALIDATION.md)。未提供其他系统或所有 SDK 组合的通过保证。

需要 Apple Command Line Tools 或完整 Xcode 提供的 Swift，以及 Python 3。无第三方 Swift 包。运行 Windows 程序还需要 Apple Rosetta 2；其安装、许可与支持范围由 Apple 管理，本项目的下载脚本不会处理。

## 获取源码与固定运行组件

```sh
git clone https://github.com/avalon-lune/MoonBridge.git
cd MoonBridge
python3 scripts/bootstrap-runtime.py
```

下载脚本按固定 SHA-256 检查 Wine stable 11.0_1、7-Zip 26.05、GStreamer 1.28.6。来源见 [固定组件记录](../metadata/runtime-sources.json)。初次执行需要联网。

所有有效载荷落在项目 `Runtime`，下载缓存落在 `Library/Cache`。GStreamer 的安装包只提取有效载荷，不执行系统安装脚本；Python 插件移到本地 DisabledPlugins，避免依赖额外 Python 框架。无需全局安装 Wine 或 GStreamer。

## 构建 App

```sh
bash scripts/build.sh
open MoonBridge.app
```

脚本使用 release 配置，将编译与模块缓存保存在 `build`，把插画和图标复制到 `MoonBridge.app` 并执行本地 ad-hoc 签名。它不提供开发者证书签名或 Apple 公证。

App 默认把自身所在目录当作项目根目录。保持 App、Runtime、Library 为同级目录；不要仅移动 App。开发时也可使用 `--root <项目目录>` 或 `MOONBRIDGE_ROOT` 指定根目录。

## 可复现检查

仓库已有源代码生成的极小 Windows 自检程序，无需购买游戏来验证基本链路。

```sh
python3 scripts/make-fixtures.py
bash scripts/build.sh
./build/swift/release/MoonBridgeCheck "$PWD"
./build/swift/release/MoonBridgeCheck "$PWD" --runtime
```

基础检查也需要 7-Zip。`--runtime` 增加真实 Win32 / Win64 执行；使用独立 `tests/work-*`，不会拿用户游戏库做试验。测试结果包含工作目录，写在本地忽略文件中。测试期间请不要手动删除它正在使用的前缀。

## 可选的 KiriKiri Z 组件

仅准备专项修复时需要：

```sh
python3 scripts/compatibility/bootstrap-kirikiri-z.py
```

脚本下载并校验官方 1.4.0r2 的 Windows x86 发行包，保留包内许可，将引擎和官方插件放入 `Runtime/Compatibility/KiriKiriZ-1.4.0.8`。它不会自动改动游戏、安装汉化或切换游戏库启动项。

已有相同官方归档时可使用 `--archive <归档路径>`；检验和准备仍会执行。后续迁移步骤见 [专项说明](compatibility/PAPER_MAGICIAN.md)。

## 仓库内容

源码、原创素材、自检源码与生成包、构建和运行库恢复脚本均随仓库提供。Wine / GStreamer 等下载载荷、构建产物、用户游戏与存档不放入 Git，避免将个人内容和大型二进制混入源代码历史。运行库可按固定来源恢复；个人存档应自行保留，不能从源码仓库恢复。

已知测试路径限制：自检入口在 `/private/tmp` 与 `/tmp` 别名混用时出现过路径不一致，未列为通过组合。请使用家目录中的实际目录；本次发布验证在本机 Local Games 下的独立构建副本运行。
