# Photo Sift

Photo Sift is a macOS app for culling a photo session shot in JPEG + RAW (Sony ARW) fast, without importing it into a catalog and without ever modifying the originals.

## The problem it solves

After a shoot, a camera set to JPEG + RAW leaves hundreds of file pairs in one folder. Sorting them in Lightroom or Photos is slow: you import everything, wait for previews, and handle each JPEG and its RAW as two separate files. Most photos need no editing or only a quick fix. A few deserve a full RAW workflow.

Photo Sift splits that pile in one keyboard-driven pass over the folder:

- **Delete** weak shots: the JPEG, ARW and sidecar go to the Trash together.
- **Fix lightly** the keepers: crop, straighten, white balance, exposure.
- **Send to the Darkroom** (*Ciemnia*) the photos worth heavy editing: only their RAW files move on to Lightroom or Apple Photos.
- **Export** everything else as finished JPEGs to an `Album/` folder.

## How it works

1. Copy the whole session, JPEG and ARW together, into one folder.
2. Open the folder in Photo Sift (⌘O). Files with the same base name (`DSC01234.JPG` + `DSC01234.ARW`) appear as one photo.
3. Review photos one by one or in a grid (G). Press ⌫ to delete and C to mark for the Darkroom. Hold Z to check focus, hold B to see the real RAW decode.
4. Edit the keepers: E for light and colour, R for crop and straightening.
5. Click **Do Ciemni** to send marked RAWs to the Darkroom target set in Settings (⌘,):
   - the `Ciemnia/` subfolder (default) — the ARW and its XMP are moved there, ready for Lightroom,
   - Apple Photos — only the RAW is imported, into an album named after the session folder.
6. Click **Eksportuj** to write the remaining photos to `Album/`. Unedited photos are copied 1:1; edited ones are rendered to JPEG with EXIF kept.

Press ? in the app for the full shortcut list.

## What Photo Sift guarantees

- **Originals are never changed.** Edits and Darkroom marks are stored as parameters in a per-photo XMP sidecar, in Photo Sift's own namespace, so Lightroom does not apply them to the RAW.
- **Export only adds and updates.** Photo Sift never deletes from `Album/` and never touches files it did not write there, such as Lightroom exports.
- **Deletion goes to the Trash.** There is no in-app undo for deletion; restore a file with *Put Back* in the Finder Trash.

The UI is in Polish. The complete behaviour spec, also in Polish, is in [`docs/workflow.md`](docs/workflow.md).

## Requirements

- macOS 26.6 or later
- Xcode with the macOS 26 SDK (Swift 6)

## Build and test

The app target lives in `PhotoSift/`; all non-UI logic is the `PhotoSiftCore` Swift package in `Core/`.

```sh
# Build the app (output: build/Build/Products/Debug/PhotoSift.app)
xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift \
  -destination 'platform=macOS' -derivedDataPath build build

# Core unit tests
swift test --package-path Core

# UI tests
xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift \
  -destination 'platform=macOS' test -only-testing:PhotoSiftUITests
```

Sample session files go in `assets/`, which is git-ignored because of their size.

## Repository layout

| Path | Contents |
| --- | --- |
| `PhotoSift/` | SwiftUI app and UI tests |
| `Core/` | `PhotoSiftCore`: scanning, sidecars, rendering, export, Photos import |
| `docs/` | Workflow spec and design prototype |
| `specifications/` | Implementation plan and verification scenarios |
