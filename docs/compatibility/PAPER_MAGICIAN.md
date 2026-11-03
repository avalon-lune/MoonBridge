# 《纸上的魔法使》专项兼容修复

记录日期：2026-11-03。本文描述特定汉化包的修复方法，资源与汉化内容由用户自行提供。仓库不含商业 XP3、生成后的汉化覆盖层或个人存档。

## 修复结果与架构

从月渡 GUI 正式启动、进入第一章后，用户确认中文、声音、新建存档及读取均正常。完整通关、OP / ED 和所有旧存档没有逐项验证。

底层仍是同一个 Wine 11 / WoW64 + Rosetta 2。新增的官方 KiriKiri Z 1.4.0.8 是 Windows x86 **游戏引擎**，用于接替此包中的旧 KiriKiri 2；它仍调用相同的 Wine 启动服务。其他游戏没有被自动切换引擎。

## 原因与排查

原包启动器是 PE32 / Intel x86 Windows 程序，不是只能在手机模拟器中打开的 Android 程序。旧引擎为 KiriKiri 2.32.2.426 / TJS2 2.4.28 / KAG 3.28，日志出现栈溢出、访问异常、旧窗口调用与配置脚本错误。

隔离副本比较过不同启动器、ASCII 路径、区域和 Windows 兼容版本、旧输入检测、全新设置及前缀、虚拟桌面、SIMD / x87 相关设置、官方原版 KiriKiri 2，以及 Wine devel 11.21。没有获得稳定的原引擎运行结果；Wine 11.21 没有部署为正式运行库。

因此采用更换游戏引擎并适配脚本的路线。这里是对当前 Mac/Wine 与旧引擎组合的兼容判断，没有宣称修复了 Wine 本身，也没有验证该原包在真实 Windows 上的表现。

## 做了哪些适配

1. 使用官方 KiriKiri Z 1.4.0.8 Windows x86 程序，并保留原 EXE。
2. 当前 `data.xp3`、`patch.xp3` 的相关文本按 CP932，汉化 `patch2.xp3` 按 GBK 读取；已有 Unicode BOM 按标记读取。合并补丁优先级，将 **106 个文本资源**写成带 BOM 的 UTF-16 LE 独立覆盖层。
3. 初始脚本仍需从原始资源启动，故使用 `.cf` 设置 `readencoding=Shift_JIS`，不添加末尾换行。这与正式配置中的中文区域不是同一个设置。
4. 在需要时加载官方 `menu.dll`、`KAGParser.dll`，移除新引擎没有的旧窗口外观赋值，并为菜单构造提供有效 Window。
5. 给 `MainWindow.tjs` 的三个旧 `setLayerPos` 调用增加存在性检查。接口缺失时跳过旧位移震屏，保留剧情推进与等待流程；没有完整重做旧震屏效果。
6. 正式启动仍使用原来的中文区域与 Windows 10 兼容设置。

原始安装保留了 31 个原文件并核对哈希；新增 EXE、CF、7 个官方插件与两个覆盖包，共 11 个文件。早期 `patch3.xp3` 含 Unicode 和基本接口适配；后补 `patch4.xp3` 为震屏保护，下次启动加载。后者结构及保护点已检查，未逐场景验证。

当前仓库的生成脚本已经将震屏保护并入完整覆盖层，所以重新生成的全量包不必与历史 `patch3.xp3` 字节相同。

## 可复现材料

- [覆盖层生成器](../../scripts/compatibility/repair-paper-magician.py)
- [官方引擎准备脚本](../../scripts/compatibility/bootstrap-kirikiri-z.py)
- [固定来源与哈希](../../metadata/compatibility-sources.json)
- [KiriKiri Z 官方发行](https://github.com/krkrz/krkrz/releases/tag/1.4.0r2)
- [官方新旧引擎迁移说明](https://krkrz.github.io/updatefromkr2.html)

引擎准备脚本下载官方 7z，核对固定 SHA-256，保留许可并验证所需 EXE / DLL。哈希是文件身份校验，不等同于官方数字签名认证。

覆盖层生成器会先校验当前三个原始 XP3 的哈希，不匹配就拒绝处理。它只读取支持的文本资源，不是任意游戏的解密器，也不自动修复其他版本。

## 手动复现步骤

先在游戏内保存并退出，备份游戏目录、最新存档、对应 Wine 前缀与游戏库条目。不要使用运行中的唯一副本做试验。

准备官方引擎：

```sh
python3 scripts/compatibility/bootstrap-kirikiri-z.py
```

在独立输出位置生成覆盖层。将 `GAME_DIR` 改为自己匹配版本的游戏实际目录：

```sh
GAME_DIR="/path/to/your/imported/game"
mkdir -p build/paper-repair
python3 scripts/compatibility/repair-paper-magician.py \
  --game-dir "$GAME_DIR" \
  --output build/paper-repair/patch3.xp3 \
  --report build/paper-repair/overlay-manifest.json
```

生成成功后，在测试副本中进行以下配置：

- 将准备目录中的 `tvpwin32.exe` 复制为游戏目录的 `MoonBridge-KiriKiriZ32.exe`，保留原 EXE。
- 将官方 `plugin` 目录中的 7 个 DLL 复制到游戏的 `plugin` 目录。先保留任何现有同名文件，不覆盖来源不明的版本。
- 将生成的 `patch3.xp3` 放入游戏目录；若已有同名或更高优先级补丁，先识别并备份，不能盲目覆盖。全量重建已包含震屏保护，不必另行重建历史 `patch4`。
- 新建 `MoonBridge-KiriKiriZ32.cf`，内容仅为 `readencoding=Shift_JIS`，没有末尾换行。
- 在月渡重新扫描，选中 `MoonBridge-KiriKiriZ32.exe`，按匹配案例使用中文区域与 Windows 10 兼容设置。
- 验证标题、剧情、中文、声音、视频、新存读档与旧进度，再考虑正式使用。

本项目没有将这些步骤包装为通用的一键迁移按钮。保持生成报告和新增文件清单，便于回退。

## 回退与验证边界

退出游戏后另存最新存档，将新增兼容文件移到单独目录，再重新选择原启动器。不要直接用修复前存档覆盖新进度。回退会同时恢复原引擎在当前环境下的问题。

排查时曾有一次进入页面后窗口消失，是隔离测试约 30 秒时限终止进程；该事件不是已确认的点击崩溃。正式 GUI 启动没有使用这个短测试时限。

该案例证明了这一份资源的基础游玩路径，不代表其他 KiriKiri 包、私有插件、全部特效或未来 macOS 都兼容。
