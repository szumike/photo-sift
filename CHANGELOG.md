# Changelog

All notable changes to Photo Sift. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

`0.x` versions come before the first stable release. Bump:

- **minor** (`0.6.0` → `0.7.0`) for a new feature or a change in behavior,
- **patch** (`0.6.0` → `0.6.1`) for fixes only.

The version lives in `MARKETING_VERSION` in `PhotoSift/PhotoSift.xcodeproj/project.xcproj`. The build number (`CURRENT_PROJECT_VERSION`) goes up by 1 with every release. Every release has a `vX.Y.Z` tag.

## 0.6.0 - 2026-11-27

### Added

- **Mark for deletion** (X or the toolbar button). The photo stays in the folder with a red badge and moves to the Trash (JPEG, ARW, XMP) only at the start of the next export. The mark is saved in the XMP.
- **Do usunięcia** filter (⌘4).
- The export sheet shows how many photos will go to the Trash. Export is available even when the only pending work is deletion.

### Changed

- A photo holds one decision at a time: X clears the Darkroom mark and C clears the deletion mark, including photos already sent to Darkroom and photos without a RAW.
- The toolbar decision buttons (Delete, Mark for deletion, Darkroom, Edit) are icons with tooltips. In a narrow window the filters show icons with counts instead of names.

## 0.5.1 - 2026-11-27

### Added

- README.

## 0.5.0 - 2026-11-26

### Added

- F mode: the photo alone on black, full screen, without toolbars or the side panel. Navigation and decisions work; editing and the grid are off.
- ⌃⌘F toggles the window's full screen.
- While zooming, `=` zooms in and `-` zooms out one level. The changed level is remembered.

## 0.4.1 - 2026-11-25

### Fixed

- "Do Ciemni" sends exactly the photos the toolbar counts and the sheet lists. A photo deleted in Photos can be sent again only after pressing C.
- A failed XMP write after an import into Photos no longer causes a second import of the same photo in the session.
- When Photos rejects an import, files are added one by one and the message names the bad file.
- A second Enter in the "Do Ciemni" sheet no longer starts another send.

## 0.4.0 - 2026-11-25

### Added

- Darkroom target in Settings (⌘,): the `Ciemnia/` folder (default) or Apple Photos. Only the RAW goes to Photos, into an album named after the session folder, without duplicates.

### Changed

- Grid thumbnails fill their tile, with no dark band.

## 0.3.0 - 2026-11-25

### Added

- Highlights and shadows (built-in macOS filter) in the model, XMP and rendering. The sliders are hidden for now.
- ↑/↓ on a focused slider: exposure in 0.1 EV steps, temperature and tint in steps of 5.

## 0.2.0 - 2026-11-25

### Added

- RAW preview: hold B to see the real decode of the ARW file.

## 0.1.0 - 2026-11-25

First version (MVP).

### Added

- Culling JPEG + ARW sessions: a file pair is one photo, single and grid views, metadata, zoom, before/after, resume position, filters.
- Immediate delete to the Trash (⌫).
- Light edits saved in XMP: 3:2 crop, straighten, white balance, exposure, white balance copy, undo and redo.
- Darkroom: mark (C) and move RAWs to `Ciemnia/`.
- Export to `Album/`: 1:1 copies or renders with edits, never deleting anything from `Album/`.
- Keyboard-first controls and a shortcut cheat sheet (?).
