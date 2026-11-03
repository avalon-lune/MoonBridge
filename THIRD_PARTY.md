# Third-party components

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
