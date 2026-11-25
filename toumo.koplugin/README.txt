Toumo 1.2.0

Place the toumo.koplugin folder in koreader/plugins/ and restart KOReader.
Open an EPUB in single-page view, then choose Tools → More tools → Toumo.
The settings menu follows KOReader's interface language: English, Chinese or Japanese.

By default odd pages look back and even pages look ahead. On page 3, page 2
shows through mirrored and page 1 appears more faintly in its original orientation.
Set the source direction, 0–4 ink layers, ink density and paper grain independently.
Choose zero layers for paper grain alone. Night mode, scrolling and two-page
view use the reader's own rendering.

Tested on a Kindle Paperwhite 3 with KOReader Tategumi v2026.10.1.
The optional PW3 accelerator is built from toumo.c. Other devices use Lua.

Source, screenshots and releases: https://github.com/shxxyz/toumo
