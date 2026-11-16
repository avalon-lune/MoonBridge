# Third-party components

## 千咲主题与系统 SQLite

0.2.1 的横幅、侧栏与默认封面使用用户指定的《新世纪福音战士》明日香、绫波丽和真希波·玛丽主题水彩改编。角色权利归原权利人；这些插画不代表官方授权或官方游戏封面，代码 MIT 许可不授予角色知识产权。具体素材与提示词见 [视觉制作记录](docs/ART_V021_PROMPTS.md)。

共享记忆使用 macOS 提供的 SQLite，通过系统链接使用，不打包其他数据库分发版。SQLite 为公有领域软件：[官方说明](https://www.sqlite.org/copyright.html)。

千咲（Chisa）角色与官方参考立绘归《鸣潮》及库洛等原权利人。`Resources/Art/chisa-avatar.png` 是以官方形象为参考、用内置图像生成工具制作的手绘 Q 版主题改编；项目代码的 MIT 许可不授予原角色知识产权。游戏库管理员身份、原创语气示例和克制傲娇风格属于月渡定制，未声称为官方设定。参考来源与生成提示见 [角色说明](docs/CHISA_PERSONA.md) 和 [头像制作记录](docs/CHISA_AVATAR_PROMPT.md)。

MoonBridge original Swift sources and probe generators use the root MIT license. External runtimes retain their own upstream licenses and notices; they are downloaded from official project releases and are not relicensed by MoonBridge. This is a local development build, not an App Store or notarized public distribution.

| Component | Pinned version | Source |
| --- | --- | --- |
| Wine macOS build / Wine | 11.0_1 / 11.0 | https://github.com/Gcenx/macOS_Wine_builds ; https://gitlab.winehq.org/wine/wine/-/tree/wine-11.0 |
| 7-Zip | 26.05 | https://github.com/ip7z/7zip/releases/tag/26.05 ; Runtime/Tools/License.txt |
| GStreamer runtime and bundled plugins | 1.28.6 | https://gstreamer.freedesktop.org/data/pkg/osx/1.28.6/ ; https://gstreamer.freedesktop.org/src/ |
| KiriKiri Z (optional) | 1.4.0.8 / 1.4.0r2 | https://github.com/krkrz/krkrz/releases/tag/1.4.0r2 ; downloaded package license.txt |
| Apple Rosetta | Host-managed | https://support.apple.com/en-gb/102527 |

Full download URLs, digests and verification status are recorded in metadata/runtime-sources.json. Wine, GStreamer, their dependencies and individual plugins have separate license terms. Preserve upstream notices and review them before distributing a derivative binary bundle. The unnecessary GStreamer Python plugin is preserved in Runtime/Media/DisabledPlugins rather than discovered at runtime, avoiding a full-Xcode Python dependency.

The original anime illustration was generated for this project with the built-in imagegen tool. Its prompt is in docs/ART_DIRECTION.md. The icon is an original code-drawn moon / bridge design. No Microsoft fonts, game assets, game files or proprietary translation patches are bundled. The tiny Windows probes are generated from the source in scripts/make-fixtures.py.

The optional KiriKiri Z bootstrap preserves its upstream license and official plugin binaries locally. The repository includes our compatibility recipe, not commercial XP3 resources or generated translation overlays. Runtime downloads are excluded from Git; the corresponding official sources and license notices remain upstream.
