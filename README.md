# Toumo (纸背透墨)

Toumo gives EPUB pages in KOReader the faint show-through of ink on thin paper. It uses the text and illustrations on the book’s actual neighboring pages, so the ink follows the book’s layout, including vertical Japanese text.

[Download the plugin](https://github.com/shxxyz/toumo/releases/latest)

## Screenshots

![Three EPUBs rendered on a Kindle Paperwhite 3 with Toumo enabled: Chinese horizontal text, Japanese vertical text, and English horizontal text.](docs/images/toumo-gallery.png)

## Installation

1. Download `toumo-v<version>.zip` from [Releases](https://github.com/shxxyz/toumo/releases).
2. Close KOReader, extract the ZIP, and copy the entire `toumo.koplugin` folder into KOReader’s `plugins/` directory. On Kindle the full path is `/mnt/us/koreader/plugins/toumo.koplugin/`. When upgrading, replace the existing folder.
3. Restart KOReader and open an EPUB in single-page view. The settings are under **Tools → More tools → Toumo**. The plugin follows KOReader’s interface language: English, Chinese (简体 / 繁體), or Japanese. Other locales use English.

## How the ink layers work

By default, odd-numbered pages draw from preceding pages and even-numbered pages draw from following ones. For example, page 5 shows a mirrored impression of page 4 and a lighter, unmirrored impression of page 3. Page 4 draws from pages 5 and 6 instead. To keep unread text out of the background, choose **Always look back**.

| Setting in the reader | What it controls |
| --- | --- |
| Source pages | Follow page parity, always look back, or always look ahead. |
| Ink layers | Choose 0–4 layers. Successive layers use approximately 100%, 44%, 20%, and 9% of the selected ink density. Use 0 for paper grain alone. |
| Ink density | Choose light, standard, or strong show-through. |
| Paper grain | Turn the grain off or choose a light or stronger texture. |

The first and last pages use only neighbors that exist. Text, inline illustrations, and full-page images can all show or contribute ink. Toumo applies in daytime, paginated, single-page EPUB view.

## Compatibility and performance

Toumo has been tested on a **Kindle Paperwhite 3 with KOReader Tategumi v2026.10.1**. While you read, it prepares the ink for the next page in your direction of travel. Text, grain, and show-through are drawn in one frame. A jump to an uncached page can take longer. If the neighboring pages fail to render or exceed the foreground wait budget, the reader uses the available layers or paper grain for that frame.

The plugin is written in Lua and ships with an optional ARMEL accelerator built from `toumo.c`. The native library loads only on the Paperwhite 3. Other devices use the Lua renderer. Hardware testing so far covers the Paperwhite 3.

## Build and test

Run `python3 tools/package.py` to produce the installable ZIP in `dist/`. To rebuild the PW3 accelerator, run `tools/build-armel.sh` first. The release was built with Zig 0.13.0. Use the `ZIG` environment variable to select the compiler executable.

With SSH configured for a Paperwhite 3, run `tools/test-pw3.sh <ssh-host>`. The on-device suite checks mirror direction, ink density, illustrated pages, prefetch, and cancellation. It uses the original EPUB fixture under `tests/`, temporary settings, and an offscreen buffer. It also verifies the English, Chinese, and Japanese menus. The test setup expects Source Han Serif JP at `koreader/fonts/SourceHanSerifJP-Regular.otf`.

## License

The plugin is released under the [MIT License](LICENSE). The book excerpts in the screenshots remain the property of their respective rights holders.
