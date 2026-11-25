# Photo Sift MVP: plan implementacji

**Goal**: Natywna aplikacja macOS realizująca cały workflow z `docs/workflow.md`: przeglądanie par JPEG + ARW, usuwanie, oznaczanie Ciemni, lekka edycja JPEG-a (kadr, prostowanie, balans bieli), wysyłka RAW-ów do `Ciemnia/` i eksport do `Album/`.

**Success Measure**: Na folderze z parami JPEG + ARW da się przejść pełny przepływ z prototypu (start → selekcja → edycja → Ciemnia → eksport) wyłącznie klawiaturą, a stan plików na dysku po każdej operacji jest zgodny z `docs/workflow.md`.

**Źródła wymagań**:
- `docs/workflow.md`: specyfikacja i decyzje (nadrzędne źródło prawdy),
- prototyp UI: https://claude.ai/artifact/HGDYhxt7DoFZ7ztvVfoS3o (układ ekranów, teksty, zachowanie).

**Do NOT touch / do NOT add**:
- Żadnej modyfikacji oryginalnych plików JPEG i ARW, poza przeniesieniem do Kosza lub do `Ciemnia/`.
- Żadnego usuwania plików z `Album/`.
- Żadnych zależności zewnętrznych (SPM, CocoaPods) ani narzędzi spoza Xcode: tylko frameworki Apple.
- Żadnej edycji `PhotoSift/PhotoSift.xcodeproj/project.xcproj` przez agentów.
- Żadnych zmian w `assets/`: to prawdziwe zdjęcia użytkownika. Testy i weryfikacja pracują na kopiach.
- Funkcji odrzuconych lub odłożonych w `docs/workflow.md`: porównanie dwóch zdjęć, Cofnij, pipeta, inne proporcje kadru, oceny i etykiety, usuwanie RAW-ów.
- Pól Adobe `crs:` w plikach XMP.

## Proposed Solution

### Architektura: logika w pakiecie, widoki w aplikacji

```
Core/                      Swift Package „PhotoSiftCore” — cała logika, testowana `swift test`
  Sources/PhotoSiftCore/       model, skanowanie, XMP, render, operacje na plikach, stan sesji
  Sources/PhotoSiftTestSupport/  generator folderów testowych (dla testów Core i UI)
  Tests/PhotoSiftCoreTests/
PhotoSift/                 projekt Xcode utworzony ręcznie z szablonu (Task 1.4)
  PhotoSift.xcodeproj
  PhotoSift/                 aplikacja SwiftUI — tylko widoki i spinanie z Core
  PhotoSiftUITests/          XCUITest na wygenerowanym folderze testowym
assets/                    prawdziwe pary JPEG + ARW z A7 III do weryfikacji (poza gitem)
```

Cała logika, łącznie ze stanem sesji (`Session`), jest w `PhotoSiftCore`. Dzięki temu jest testowalna szybko, bez uruchamiania aplikacji. Aplikacja zawiera wyłącznie widoki SwiftUI (z AppKitem tam, gdzie SwiftUI nie wystarcza) oraz spięcie klawiatury.

### Kluczowe decyzje techniczne

- **Bez sandboxa.** Aplikacja jest osobista, poza App Store. Brak sandboxa upraszcza dostęp do folderów: nie są potrzebne security-scoped bookmarks.
- **Kolejność zdjęć:** według daty wykonania z EXIF, a przy remisie lub braku daty według nazwy pliku.
- **Podgląd** zawsze z JPEG-a, zdekodowanego w rozmiarze ekranu. Pełna rozdzielczość jest dekodowana dopiero przy zoomie 100%. Dla zdjęcia tylko z RAW-em używana jest miniatura osadzona w ARW (bez dekodowania RAW-a).
- **Edycje** to parametry (`EditParams`) w pliku XMP pary, we własnej przestrzeni nazw `photosift`. Zapis jest automatyczny (z opóźnieniem po ostatniej zmianie), a przycisku „Zapisz” nie ma.
- **Render** przez Core Image: obrót o kąt, kadr, `CITemperatureAndTint`. Ten sam potok obsługuje podgląd na żywo i eksport.
- **Eksport** rozpoznaje swoje pliki w `Album/` bez dodatkowego pliku z listą:
  - kopia bez edycji jest identyczna bajt w bajt z oryginałem,
  - wyrenderowany JPEG ma w osadzonym XMP znacznik `photosift:editFingerprint`,
  - każdy inny plik jest obcy i nigdy nie jest ruszany.

### Kontrakty

```swift
public struct PhotoItem: Identifiable, Sendable, Equatable {
    public let id: String            // nazwa bazowa, np. "DSC01234"
    public var jpegURL: URL?
    public var rawURL: URL?          // ARW w folderze sesji (nil, gdy brak lub już w Ciemnia/)
    public var sidecarURL: URL       // <folder>/<id>.xmp — może jeszcze nie istnieć
    public var isSentToDarkroom: Bool // Ciemnia/<id>.ARW istnieje
    public var captureDate: Date?
    public var isRawOnly: Bool { get } // jpegURL == nil
}

public enum CropOrientation: String, Codable, Sendable { case landscape, portrait } // 3:2 / 2:3

public struct EditParams: Codable, Equatable, Sendable {
    public var crop: CGRect          // znormalizowany 0...1 w przestrzeni wyprostowanego obrazu
    public var orientation: CropOrientation
    public var angle: Double         // stopnie, -45...45
    public var temperature: Double   // -100...100, 0 = bez zmiany
    public var tint: Double          // -100...100, 0 = bez zmiany
    public static func identity(for imageSize: CGSize) -> EditParams
    public var isIdentity: Bool { get }
    public var fingerprint: String { get } // stabilny skrót parametrów, zapisywany w eksporcie
}

public struct SidecarState: Equatable, Sendable {
    public var edit: EditParams?     // nil = brak edycji
    public var markedForDarkroom: Bool
}

public enum ExportStatus: Equatable, Sendable {
    case notExported        // brak pliku w Album/
    case current            // nasz plik, aktualny
    case changed            // nasz plik, nieaktualny
    case skipped(SkipReason) // Ciemnia, tylko RAW
    case conflict           // obcy plik o tej samej nazwie — nie ruszamy
}
```

Kontrakty mogą zostać uzupełnione przez implementujących, ale nie zmienione bez aktualizacji planu.

## Open Questions

Wszystkie pytania są rozstrzygnięte.

| # | Pytanie | Odpowiedź |
| --- | --- | --- |
| 1 | Jak powstaje projekt Xcode? | Ręcznie, z szablonu Xcode (Task 1.4), bez XcodeGen. Szablon używa folderów synchronizowanych, więc agenci nie edytują `project.xcproj`. |
| 2 | Czy inicjujemy repozytorium git przed implementacją? | Tak, repozytorium jest już założone. |
| 3 | Co robi C na zdjęciu bez pliku RAW (tylko JPEG)? | Nic nie oznacza. Pokazuje komunikat „Brak pliku RAW — nie można wysłać do Ciemni”. |
| 4 | Prawdziwe pliki testowe? | `assets/`: 4 pary z A7 III (DSC01906, DSC02181, DSC02416, DSC02418). JPEG-i mają 3936×2624 (rozmiar M), ARW 6000×4000. Folder jest wykluczony z gita. |

## Technical Context

- **Narzędzia:** Xcode 27.2 (SDK macOS 27.2), Swift 6.4.2, Apple M4, macOS 27.2. Xcode zaktualizował się w trakcie implementacji z 26.2; pakiet `Core` deklaruje swift-tools-version 6.2, co nadal jest poprawne.
- **Cel wdrożenia:** macOS 26.6 (ustawione w projekcie). Swift 6 language mode ze ścisłą współbieżnością.
- **Frameworki:** SwiftUI, AppKit (gdzie konieczny), ImageIO, Core Image, UniformTypeIdentifiers. Brak zależności zewnętrznych.
- **Projekt Xcode:** `PhotoSift/PhotoSift.xcodeproj`, utworzony ręcznie z szablonu i commitowany do repozytorium. Szablon używa folderów synchronizowanych: każdy plik dodany do `PhotoSift/PhotoSift/` lub `PhotoSift/PhotoSiftUITests/` jest automatycznie kompilowany w odpowiednim celu. **Agenci nigdy nie edytują `project.xcproj`.** Zmiana wymagająca nowego celu, ustawienia builda lub zależności to zadanie dla użytkownika. Wyjątek za zgodą użytkownika (2026-11-25): dopisane `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` w celu PhotoSift.
- **Bez zależności zewnętrznych i bez narzędzi spoza Xcode.**
- **Testy:** Swift Testing (`import Testing`, `@Suite`, `@Test`) w `Core/Tests/PhotoSiftCoreTests`, a XCTest/XCUITest w `PhotoSift/PhotoSiftUITests/`.
- **Nazewnictwo plików testowych:** `<Typ>Tests.swift` z `@Suite` o tej samej nazwie, np. `ScannerTests`. Klasy UI testów: `<Obszar>UITests`.

### Konwencje

- Typy domenowe i usługi w Core mają `public` API i są `Sendable`. Stan sesji (`Session`) to `@MainActor @Observable`. Dekodowanie obrazów i operacje na plikach działają poza głównym wątkiem (aktory lub `async`).
- Nazwy w kodzie po angielsku. Teksty w UI po polsku, dokładnie jak w prototypie.
- Każdy interaktywny element UI ma `accessibilityIdentifier` (np. `toolbar.export`, `grid.cell.DSC01234`). Testy UI opierają się wyłącznie na identyfikatorach.
- Aplikacja przyjmuje argument uruchomienia `--open-folder <ścieżka>`, który od razu otwiera folder. Używają go testy UI.
- Operacje na plikach nigdy nie wywołują `removeItem` na plikach użytkownika: usuwanie odbywa się przez `FileManager.trashItem`. Zapis plików jest atomowy (plik tymczasowy, potem zamiana).

### Zadania UI wykonujemy po kolei, nie równolegle

Grupy D, E i F (Fazy 5–7) wykonujemy sekwencyjnie, mimo że zadania mają rozłączne pliki. Powody:
- wszystkie pliki aplikacji kompilują się w jednym celu, więc niedokończony plik jednego agenta psuje build drugiego,
- testy UI przejmują jedyny ekran i klawiaturę Maca, więc dwa przebiegi naraz się wzajemnie psują.

Testy UI wymagają odblokowanego ekranu.

### Prototyp UI jako źródło dla zadań interfejsu

- Kod prototypu: `docs/design/prototype.dc.html`. To jeden komponent HTML ze wszystkimi ekranami, wybieranymi stanem `initial`:
  - markup (układ, teksty, identyfikatory) w liniach ok. 75–548,
  - logika (zachowanie klawiszy, komunikaty, przejścia) w liniach ok. 549–1212.
- Z prototypu bierzemy układ, kolory, teksty i zachowanie. Nie przenosimy HTML-a 1:1: aplikacja używa natywnych kontrolek SwiftUI.
- **Przy rozbieżności wygrywa `docs/workflow.md`.** Znane różnice:
  - pasek miniatur ma tylko pojedyncze zaznaczenie,
  - w kodzie prototypu zostały resztki ekspozycji, której nie implementujemy.
- API `Session` i pozostałych typów `Core`: czytaj bezpośrednio pliki w `Core/Sources/PhotoSiftCore/`.

### Komendy weryfikacji (dosłownie)

| Cel | Komenda |
| --- | --- |
| Testy jednej suity Core | `swift test --package-path Core --filter <NazwaSuity>` |
| Wszystkie testy Core | `swift test --package-path Core` |
| Kontrola ustawień projektu | `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -showBuildSettings \| grep -E 'ENABLE_APP_SANDBOX\|MACOSX_DEPLOYMENT_TARGET\|SWIFT_VERSION'` |
| Build aplikacji | `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' build` |
| Jedna klasa testów UI | `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/<Klasa>` |
| Wszystkie testy UI | `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests` |
| Build do weryfikacji (stała ścieżka `.app`) | `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' -derivedDataPath build build` → `build/Build/Products/Debug/PhotoSift.app` |
| Uruchomienie na folderze | `open -n build/Build/Products/Debug/PhotoSift.app --args --open-folder <ścieżka>` |

Linter nie jest zainstalowany i nie jest częścią planu.

## Phases and Tasks

### Faza 1: Fundament

**Goal:** Działający szkielet: pakiet Core, aplikacja, testy UI i generator danych testowych.
**Verification:** `swift test --package-path Core` oraz `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/LaunchUITests`

Kolejność: 1.1, potem równolegle 1.2, 1.3 i 1.4 (ręcznie, użytkownik), na końcu 1.5.

- [x] **Task 1.1: Pakiet Core.** Utwórz pakiet `Core` (swift-tools-version 6.2, platforma macOS 26) z bibliotekami `PhotoSiftCore` i `PhotoSiftTestSupport` (zależną od `PhotoSiftCore`) oraz celem testów `PhotoSiftCoreTests`.
  - **Files:** create `Core/Package.swift`, create `Core/Sources/PhotoSiftCore/PhotoSiftCore.swift`, create `Core/Sources/PhotoSiftTestSupport/TestSupport.swift`, create `Core/Tests/PhotoSiftCoreTests/SmokeTests.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter SmokeTests` przechodzi

- [x] **Task 1.2: Generator folderów testowych.** W `PhotoSiftTestSupport` dodaj `FixtureFolder`, który tworzy w katalogu tymczasowym folder sesji o zadanym składzie:
  - pary JPEG + ARW,
  - same JPEG-i,
  - same ARW-y,
  - opcjonalnie istniejące podfoldery `Ciemnia/` i `Album/` z plikami.

  JPEG-i są generowane programowo (rozpoznawalny wzór, rozmiar 600×400 albo 400×600) z EXIF-em: model, obiektyw, ISO, przysłona, czas, ogniskowa, data. „ARW” to plik JPEG z rozszerzeniem `.ARW`: ImageIO odczyta z niego podgląd tak jak z miniatury osadzonej. Generator zwraca URL folderu i listę nazw bazowych.
  - **Files:** create `Core/Sources/PhotoSiftTestSupport/FixtureFolder.swift`, modify `Core/Sources/PhotoSiftTestSupport/TestSupport.swift` (created in Task 1.1) lub usuń go, jeśli zbędny, create `Core/Tests/PhotoSiftCoreTests/FixtureFolderTests.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter FixtureFolderTests` przechodzi
    - [x] test potwierdza, że wygenerowany JPEG ma odczytywalne przez ImageIO pola EXIF: `ISOSpeedRatings`, `FNumber`, `ExposureTime`, `FocalLength`, `LensModel`, `DateTimeOriginal`

- [x] **Task 1.3: Typy domenowe.** Utwórz typy z sekcji Kontrakty: `PhotoItem`, `CropOrientation`, `EditParams` (z `identity(for:)`, `isIdentity` i `fingerprint`) oraz `SidecarState`. `fingerprint` musi być stabilny między uruchomieniami: skrót kanonicznej reprezentacji, nie `hashValue`.
  - **Files:** create `Core/Sources/PhotoSiftCore/Model/PhotoItem.swift`, create `Core/Sources/PhotoSiftCore/Model/EditParams.swift`, create `Core/Sources/PhotoSiftCore/Model/SidecarState.swift`, create `Core/Tests/PhotoSiftCoreTests/EditParamsTests.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter EditParamsTests` przechodzi. Testy pokrywają: `identity(for:)` dla obrazu poziomego i pionowego, `isIdentity`, stabilność i różnicowanie `fingerprint`, kodowanie i dekodowanie.

Parallel group: Tasks 1.2, 1.3 i 1.4 są niezależne i mają rozłączne pliki. Wszystkie zależą od Task 1.1.

- [x] **Task 1.4 (RĘCZNIE, użytkownik): Projekt Xcode.**
  1. Xcode → File → New → Project… → macOS → **App** → Next.
  2. Ustawienia projektu:
     - Product Name: `PhotoSift`,
     - Team: None,
     - Organization Identifier: dowolny, np. `pl.photosift`,
     - Interface: SwiftUI, Language: Swift,
     - Testing System: **Swift Testing with XCUITest**,
     - Storage: None.
  3. Lokalizacja: folder `photo-sift` (główny folder repozytorium). Xcode utworzy w nim `PhotoSift/PhotoSift.xcodeproj`.
  4. Cel PhotoSift → **General** → Minimum Deployments: **macOS 26.0**.
  5. Cel PhotoSift → **Signing & Capabilities**:
     - usuń capability **App Sandbox** (ikona kosza przy sekcji),
     - Signing Certificate: „Sign to Run Locally”.
  6. Cel PhotoSift → **Build Settings** → Swift Language Version: **Swift 6**.
  7. File → **Add Package Dependencies…** → **Add Local…** → wybierz folder `photo-sift/Core` → Add Package. W oknie wyboru produktów:
     - `PhotoSiftCore` → cel **PhotoSift**,
     - `PhotoSiftTestSupport` → cel **PhotoSiftUITests**.
  8. ⌘B: build kończy się sukcesem.
  - **Files:** create `PhotoSift/PhotoSift.xcodeproj` (z szablonu), create `PhotoSift/PhotoSift/MyApp.swift`, `PhotoSift/PhotoSift/ContentView.swift`, `PhotoSift/PhotoSiftUITests/*` i `PhotoSift/PhotoSiftTests/*` (z szablonu)
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' build` kończy się sukcesem
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -showBuildSettings | grep -E 'ENABLE_APP_SANDBOX|MACOSX_DEPLOYMENT_TARGET|SWIFT_VERSION'` pokazuje `ENABLE_APP_SANDBOX = NO` (lub brak tej linii), `MACOSX_DEPLOYMENT_TARGET = 26.6` i `SWIFT_VERSION = 6.0`

- [x] **Task 1.5: Szkielet aplikacji.** Dodaj minimalne okno z tytułem „Photo Sift” i obsługą argumentu `--open-folder <ścieżka>` (na tym etapie tylko zapamiętuje ścieżkę). Usuń szablonowe `ContentView.swift` oraz szablonowe pliki testów UI i zastąp je `LaunchUITests`.
  - **Files:** modify `PhotoSift/PhotoSift/MyApp.swift` (created in Task 1.4), delete `PhotoSift/PhotoSift/ContentView.swift`, create `PhotoSift/PhotoSift/LaunchArguments.swift`, delete szablonowe pliki w `PhotoSift/PhotoSiftUITests/`, create `PhotoSift/PhotoSiftUITests/LaunchUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' build` kończy się sukcesem
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/LaunchUITests` przechodzi (test sprawdza, że okno „Photo Sift” się otwiera)
  - **Stop Rule:** Jeśli build nie widzi nowych plików albo wymaga zmiany w `project.xcproj`, zatrzymaj się i zgłoś. Nie edytuj pliku projektu.
  - **Clues:** Pierwsze uruchomienie testów UI może wymagać zgody systemu na sterowanie (Accessibility/Automation). Jeśli test wisi na takim oknie, zgłoś to zamiast obchodzić.

### Faza 2: Domena

**Goal:** Odczyt folderu, metadanych, plików XMP i render edycji.
**Verification:** `swift test --package-path Core`

Parallel group A: Tasks 2.1, 2.2, 2.3 są niezależne i mają rozłączne pliki.

- [x] **Task 2.1: Skanowanie folderu i metadane.**
  - `FolderScanner` zwraca `[PhotoItem]` dla folderu sesji:
    - rozpoznaje `.jpg`, `.jpeg` i `.arw` bez względu na wielkość liter,
    - grupuje pliki po nazwie bazowej,
    - pomija podfoldery i inne pliki,
    - ustawia `isSentToDarkroom`, gdy istnieje `Ciemnia/<id>.ARW`,
    - sortuje według `captureDate`, a potem po nazwie.
  - `PhotoMetadata` odczytuje z EXIF: aparat, obiektyw, ISO, przysłonę, czas, ogniskową i datę. Formatuje je jak w prototypie, np. „ISO 400”, „f/4”, „1/250 s”, „35 mm”.
  - **Files:** reuse `Core/Sources/PhotoSiftCore/Model/PhotoItem.swift` (created in Task 1.3), create `Core/Sources/PhotoSiftCore/Scanning/FolderScanner.swift`, create `Core/Sources/PhotoSiftCore/Metadata/PhotoMetadata.swift`, create `Core/Tests/PhotoSiftCoreTests/FolderScannerTests.swift`, create `Core/Tests/PhotoSiftCoreTests/PhotoMetadataTests.swift`, reuse `Core/Sources/PhotoSiftTestSupport/FixtureFolder.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter FolderScannerTests` przechodzi. Testy pokrywają: parowanie, same JPEG-i, same ARW-y, wielkość liter rozszerzeń, pomijanie `Ciemnia/` i `Album/`, `isSentToDarkroom`, kolejność.
    - [x] `swift test --package-path Core --filter PhotoMetadataTests` przechodzi. Testy pokrywają odczyt i formatowanie wszystkich pól oraz brak pola.
  - **Clues:** `CGImageSourceCopyPropertiesAtIndex` z opcją `kCGImageSourceShouldCache: false` czyta tylko nagłówki, bez dekodowania obrazu.

- [x] **Task 2.2: Plik XMP pary.** `SidecarStore` czyta i zapisuje `SidecarState` w `<folder>/<id>.xmp`, w przestrzeni nazw `photosift`. Wymagania:
  - przy zapisie zachowuje wszystkie inne pola istniejącego pliku XMP,
  - zapisuje atomowo,
  - `clearPhotoSiftFields(at:)` usuwa wszystkie pola `photosift`, a pozostałe zostawia,
  - przy braku edycji i braku oznaczenia Ciemni nie tworzy pliku, a jeśli plik zawiera tylko pola `photosift`, usuwa go.

  Używaj wyłącznie pól `photosift:`, nigdy `crs:`.
  - **Files:** create `Core/Sources/PhotoSiftCore/Sidecar/SidecarStore.swift`, create `Core/Tests/PhotoSiftCoreTests/SidecarStoreTests.swift`, reuse `Core/Sources/PhotoSiftCore/Model/SidecarState.swift` i `Core/Sources/PhotoSiftCore/Model/EditParams.swift` (created in Task 1.3)
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter SidecarStoreTests` przechodzi. Testy pokrywają: zapis i odczyt w obie strony, zachowanie obcych pól (np. `xmp:Rating` dopisany w teście), `clearPhotoSiftFields`, brak pliku przy pustym stanie, brak jakiegokolwiek `crs:` w zapisanym pliku.
  - **Clues:** `CGImageMetadataCreateFromXMPData`, `CGImageMetadataRegisterNamespaceForPrefix`, `CGImageMetadataSetValueWithPath`, `CGImageMetadataCreateXMPData`. Przestrzeń nazw: `http://ns.photosift.app/1.0/`, prefiks `photosift`.

- [x] **Task 2.3: Render edycji.**
  - `EditRenderer` buduje `CIImage` z JPEG-a i `EditParams`, w kolejności: orientacja EXIF, obrót o `angle` wokół środka, kadr, temperatura i tint. Ten sam potok obsługuje podgląd i eksport.
  - Funkcja pomocnicza `constrainCrop` dopasowuje kadr tak, żeby po obrocie mieścił się w obrazie bez pustych narożników i zachowywał proporcje 3:2 lub 2:3.
  - **Files:** create `Core/Sources/PhotoSiftCore/Rendering/EditRenderer.swift`, create `Core/Sources/PhotoSiftCore/Rendering/CropGeometry.swift`, create `Core/Tests/PhotoSiftCoreTests/EditRendererTests.swift`, reuse `Core/Sources/PhotoSiftCore/Model/EditParams.swift` (created in Task 1.3), reuse `Core/Sources/PhotoSiftTestSupport/FixtureFolder.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter EditRendererTests` przechodzi. Testy pokrywają:
      - render tożsamości daje wymiary oryginału,
      - kadr 50% daje oczekiwane wymiary w pikselach w proporcji 3:2,
      - zmiana orientacji daje 2:3,
      - `constrainCrop` przy kącie 10° nie zostawia pustych narożników,
      - dodatnia temperatura zwiększa średnią składową czerwoną względem niebieskiej.
  - **Clues:** `CITemperatureAndTint` z `inputNeutral` (6500, 0) i `inputTargetNeutral` przesuniętym proporcjonalnie do suwaków. Stałe mapowania trzymaj w jednym miejscu.

### Faza 3: Operacje na plikach

**Goal:** Usuwanie do Kosza, przenoszenie do Ciemni i eksport do Albumu, każde zgodne z zasadami bezpieczeństwa z `docs/workflow.md`.
**Verification:** `swift test --package-path Core`

Parallel group B: Tasks 3.1, 3.2, 3.3 są niezależne i mają rozłączne pliki. Wszystkie zależą od Fazy 2.

- [x] **Task 3.1: Usuwanie do Kosza.** `PhotoTrasher.trash(_ item: PhotoItem)` przenosi do Kosza JPEG, ARW i XMP (te, które istnieją) przez `FileManager.trashItem`. Nie dotyka `Album/` ani `Ciemnia/`. Zwraca listę przeniesionych plików, a przy częściowym błędzie raportuje, których plików nie przeniesiono.
  - **Files:** create `Core/Sources/PhotoSiftCore/FileOps/PhotoTrasher.swift`, create `Core/Tests/PhotoSiftCoreTests/PhotoTrasherTests.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter PhotoTrasherTests` przechodzi. Testy pokrywają: para z XMP, sam JPEG, sam ARW oraz to, że plik w `Album/` o tej samej nazwie pozostaje nietknięty.

- [x] **Task 3.2: Wysyłka do Ciemni.** `DarkroomMover.send(_ items: [PhotoItem])` przenosi `<id>.ARW` oraz `<id>.xmp` (jeśli istnieje) do `<folder>/Ciemnia/`, tworząc folder w razie potrzeby. Po przeniesieniu wywołuje `SidecarStore.clearPhotoSiftFields` na przeniesionym XMP. JPEG zostaje na miejscu. Jeśli plik docelowy już istnieje, zdjęcie jest pomijane i trafia do raportu jako konflikt, bez nadpisywania.
  - **Files:** create `Core/Sources/PhotoSiftCore/FileOps/DarkroomMover.swift`, create `Core/Tests/PhotoSiftCoreTests/DarkroomMoverTests.swift`, reuse `Core/Sources/PhotoSiftCore/Sidecar/SidecarStore.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter DarkroomMoverTests` przechodzi. Testy pokrywają: przeniesienie ARW i XMP, pozostawienie JPEG-a, brak pól `photosift` w przeniesionym XMP, utworzenie `Ciemnia/`, konflikt bez nadpisania.

- [x] **Task 3.3: Eksport do Albumu.** `AlbumExporter` ma dwa kroki:
  1. `plan(items:edits:) -> ExportPlan` wylicza `ExportStatus` dla każdego zdjęcia, sprawdzając rzeczywisty stan `Album/`:
     - zdjęcia z Ciemni (oznaczone lub wysłane) i zdjęcia tylko z RAW-em dostają `skipped`,
     - plik identyczny z oryginałem: `current` dla zdjęcia bez edycji, `changed` dla zdjęcia z edycją,
     - plik ze znacznikiem `photosift:editFingerprint`: `current`, gdy znacznik zgadza się z bieżącymi edycjami, w przeciwnym razie `changed`,
     - każdy inny plik o tej samej nazwie: `conflict`.
  2. `run(plan:progress:)` wykonuje eksport:
     - `notExported` i `changed` zdjęć bez edycji kopiuje przez `FileManager.copyItem` (klon APFS),
     - zdjęcia z edycją renderuje do JPEG-a (jakość 0,95) z zachowanym EXIF-em, orientacją ustawioną na 1, poprawionymi wymiarami i znacznikiem w osadzonym XMP,
     - podmienia pliki atomowo, obsługuje anulowanie i zwraca podsumowanie.

  Eksport nigdy nie usuwa plików z `Album/` i nigdy nie dotyka plików `conflict`.
  - **Files:** create `Core/Sources/PhotoSiftCore/Export/ExportStatus.swift`, create `Core/Sources/PhotoSiftCore/Export/AlbumExporter.swift`, create `Core/Tests/PhotoSiftCoreTests/AlbumExporterTests.swift`, reuse `Core/Sources/PhotoSiftCore/Rendering/EditRenderer.swift`, reuse `Core/Sources/PhotoSiftCore/Model/EditParams.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter AlbumExporterTests` przechodzi. Testy pokrywają:
      - pierwszy eksport: kopie bez edycji są bajt w bajt identyczne z oryginałami,
      - plik z edycją ma wymiary kadru i zachowany EXIF (ISO, przysłona, model),
      - pominięcie Ciemni i zdjęć tylko z RAW-em,
      - ponowny eksport bez zmian nic nie zapisuje,
      - zmiana edycji daje `changed`, a po eksporcie `current`,
      - reset edycji zdjęcia wcześniej eksportowanego z edycją daje `changed`, a eksport przywraca kopię 1:1,
      - obcy plik o tej samej nazwie daje `conflict` i pozostaje nietknięty,
      - plik w `Album/` bez odpowiednika w sesji pozostaje nietknięty,
      - w `Album/` po eksporcie są wyłącznie pliki `.jpg` lub `.JPG`.
  - **Clues:**
    - Nazwa w `Album/` jest taka sama jak nazwa oryginalnego JPEG-a.
    - Porównanie identyczności: najpierw rozmiar, potem `FileManager.contentsEqual(atPath:andPath:)`.
    - Zapis z metadanymi: `CGImageDestinationAddImageAndMetadata` z właściwościami źródła i metadanymi XMP.

### Faza 4: Stan sesji i ładowanie obrazów

**Goal:** Cała logika aplikacji w Core: nawigacja, decyzje, zaznaczenie, filtry, edycje, liczniki i wydajne ładowanie obrazów.
**Verification:** `swift test --package-path Core`

Parallel group C: Tasks 4.1, 4.2, 4.3 są niezależne i mają rozłączne pliki.

- [x] **Task 4.1: Model sesji.** `Session` (`@MainActor @Observable`) ładuje folder przez `FolderScanner` i `SidecarStore` i udostępnia stan oraz akcje zgodnie z `docs/workflow.md` i prototypem.

  **Stan:**
  - zdjęcia, bieżące zdjęcie, zaznaczenie (wiele tylko w trybie siatki),
  - widok `single` lub `grid`, tryb `browse` lub `edit`, narzędzie `color` lub `crop`,
  - filtr `all`, `darkroom` lub `edited`, flaga „wszystko przejrzane”,
  - schowek balansu bieli,
  - liczniki: do Ciemni, do eksportu, usunięte w tej sesji.

  **Akcje:**
  - `next` i `previous` (po ostatnim zdjęciu ustawia „wszystko przejrzane”),
  - `delete` (bieżące albo zaznaczone w siatce, przez `PhotoTrasher`, z przejściem dalej),
  - `toggleDarkroom` (bieżące albo zaznaczone w siatce; zapis do XMP; dla zdjęcia bez RAW-a zwraca komunikat „Brak pliku RAW — nie można wysłać do Ciemni”, a dla zdjęcia już wysłanego „RAW jest już w Ciemnia/”, bez zmiany stanu),
  - `setFilter`, `toggleView`, `openInSingle(id)`, `select(id, modifiers)`, `selectAll`, `clearSelection`,
  - `updateEdit` (blokada dla Ciemni i zdjęć tylko z RAW-em, zapis do XMP z opóźnieniem ok. 300 ms),
  - `resetEdit`, `copyWhiteBalance`, `pasteWhiteBalance` (na zaznaczone, z pominięciem zablokowanych i raportem liczby),
  - `sendToDarkroom` (przez `DarkroomMover`),
  - `exportPlan` i `runExport` (przez `AlbumExporter`).

  Każda akcja zwraca lub publikuje komunikat dla UI (tekst i podtekst, jak w prototypie). `Session` przyjmuje w inicjalizatorze identyfikator zdjęcia startowego (wznowienie), a bieżący identyfikator wystawia do zapamiętania.
  - **Files:** create `Core/Sources/PhotoSiftCore/Session/Session.swift`, create `Core/Sources/PhotoSiftCore/Session/SessionTypes.swift`, create `Core/Sources/PhotoSiftCore/Session/Toast.swift`, create `Core/Tests/PhotoSiftCoreTests/SessionNavigationTests.swift`, create `Core/Tests/PhotoSiftCoreTests/SessionDecisionTests.swift`, create `Core/Tests/PhotoSiftCoreTests/SessionEditTests.swift`, reuse wszystkich typów z Faz 2 i 3
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter SessionNavigationTests` przechodzi. Testy pokrywają: kolejność, „wszystko przejrzane” po ostatnim zdjęciu, powrót strzałką, filtry, przełączanie widoku, zaznaczanie z ⌘ i ⇧ tylko w siatce.
    - [x] `swift test --package-path Core --filter SessionDecisionTests` przechodzi. Testy pokrywają: usunięcie z przejściem dalej, usunięcie zaznaczonych w siatce, przełączanie Ciemni z przejściem dalej, C na zdjęciu bez RAW-a, C na zdjęciu już wysłanym, liczniki, `sendToDarkroom`.
    - [x] `swift test --package-path Core --filter SessionEditTests` przechodzi. Testy pokrywają: blokadę edycji dla Ciemni i zdjęć tylko z RAW-em, zapis do XMP, reset, kopiuj i wklej balans bieli na zaznaczone z pominięciem zablokowanych, filtr „Edytowane”.

- [x] **Task 4.2: Ładowanie obrazów.** Aktor `ImageLoader` udostępnia:
  - miniaturę (ok. 320 px),
  - podgląd w rozmiarze ekranu,
  - pełną rozdzielczość (do zoomu 100%),
  - podgląd zdjęcia tylko z RAW-em z miniatury osadzonej w ARW.

  Ma pamięć podręczną z limitem i `prefetch(ids:)` dla sąsiednich zdjęć (±2). Obrazy są zawsze obrócone zgodnie z orientacją EXIF.
  - **Files:** create `Core/Sources/PhotoSiftCore/Images/ImageLoader.swift`, create `Core/Tests/PhotoSiftCoreTests/ImageLoaderTests.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter ImageLoaderTests` przechodzi. Testy pokrywają: wymiary miniatury i podglądu, orientację, podgląd z „ARW”, trafienie w pamięć podręczną przy drugim odczycie.
  - **Clues:** `CGImageSourceCreateThumbnailAtIndex` z `kCGImageSourceThumbnailMaxPixelSize` i `kCGImageSourceCreateThumbnailWithTransform: true`. Dla ARW użyj `kCGImageSourceCreateThumbnailFromImageIfAbsent: true`, nigdy `...Always`, bo to wymusiłoby dekodowanie RAW-a.

- [x] **Task 4.3: Pamięć między uruchomieniami.** `ResumeStore` zapamiętuje ostatnie zdjęcie dla każdego folderu, z kluczem po ścieżce. `RecentFoldersStore` przechowuje do 8 ostatnich folderów z nazwą, ścieżką, liczbą zdjęć i datą, a nieistniejące foldery pomija przy odczycie. Oba magazyny korzystają z `UserDefaults` wstrzykiwanego w testach.
  - **Files:** create `Core/Sources/PhotoSiftCore/Persistence/ResumeStore.swift`, create `Core/Sources/PhotoSiftCore/Persistence/RecentFoldersStore.swift`, create `Core/Tests/PhotoSiftCoreTests/PersistenceTests.swift`
  - **Definition of Done:**
    - [x] `swift test --package-path Core --filter PersistenceTests` przechodzi

### Faza 5: Przeglądanie (UI)

**Goal:** Ekrany startu, przeglądania i siatki, sterowane klawiaturą, zgodne z prototypem.
**Verification:** `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests`

- [x] **Task 5.1: Szkielet okna i klawiatura.**
  - **Okno:** główne okno z paskiem narzędzi jak w prototypie:
    - nawigacja z pozycją „124 / 512”,
    - przełącznik widoku i filtry z licznikami,
    - przyciski Usuń, Ciemnia, Edycja i ?,
    - przyciski „Wyślij do Ciemni (n)” i „Eksportuj (n)” wyłączone przy zerze.
  - **Routing ekranów:** start, pusty folder, główny.
  - **Komunikaty:** prezentacja komunikatów (toast) z `Session`.
  - **Klawiatura:** centralny `KeyboardRouter`, który mapuje wszystkie skróty z tabeli w `docs/workflow.md` na akcje `Session` i obsługuje przytrzymanie Z i M (keyDown/keyUp, z ignorowaniem powtórzeń).
  - **Argument `--open-folder`** otwiera folder od razu.
  - **Wznowienie:** zapis pozycji przy zmianie zdjęcia i komunikat „Wznowiono od zdjęcia X z Y”.

  - **Wspólne elementy dla zadań równoległych:**
    - `ViewState` przechowuje stan wyłącznie widokowy: `isZoomHeld`, `isBeforeHeld`, punkt zoomu i aktywny komunikat,
    - `StatusBadges` to znaczniki Ciemnia, edytowane, stan Albumu, RAW i blokada, używane przez podgląd, pasek miniatur i siatkę,
    - zaślepki (pusty widok z identyfikatorem dostępności) wszystkich ekranów, arkuszy i nakładek, do których odwołuje się `MainWindow`. Późniejsze zadania tylko je wypełniają, więc nie modyfikują `MainWindow`.
  - **Files:** modify `PhotoSift/PhotoSift/MyApp.swift` (created in Task 1.4), modify `PhotoSift/PhotoSift/LaunchArguments.swift` (created in Task 1.5), create `PhotoSift/PhotoSift/MainWindow.swift`, create `PhotoSift/PhotoSift/Toolbar/MainToolbar.swift`, create `PhotoSift/PhotoSift/Keyboard/KeyboardRouter.swift`, create `PhotoSift/PhotoSift/Common/ToastView.swift`, create `PhotoSift/PhotoSift/Common/ViewState.swift`, create `PhotoSift/PhotoSift/Common/StatusBadges.swift`, create zaślepki: `PhotoSift/PhotoSift/Screens/StartScreen.swift`, `PhotoSift/PhotoSift/Screens/EmptyFolderScreen.swift`, `PhotoSift/PhotoSift/Screens/SingleView/SinglePhotoView.swift`, `PhotoSift/PhotoSift/Screens/Grid/GridView.swift`, `PhotoSift/PhotoSift/Screens/ShortcutsOverlay.swift`, `PhotoSift/PhotoSift/Screens/Edit/EditPanel.swift`, `PhotoSift/PhotoSift/Screens/Edit/EditStage.swift`, `PhotoSift/PhotoSift/Sheets/DarkroomSheet.swift`, `PhotoSift/PhotoSift/Sheets/ExportSheet.swift`; create `PhotoSift/PhotoSiftUITests/ToolbarUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' build` kończy się sukcesem
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/ToolbarUITests` przechodzi. Testy pokrywają: otwarcie folderu z argumentu, licznik pozycji, zmianę zdjęcia strzałkami, wyłączone „Eksportuj”, gdy nie ma czego eksportować.
  - **Clues:** Obsługa klawiszy z przytrzymaniem wymaga zdarzeń keyUp, więc w SwiftUI użyj `onKeyPress(phases: [.down, .up])` albo lokalnego `NSEvent.addLocalMonitorForEvents`. Pole tekstowe ani suwak z fokusem nie może przechwytywać ←/→ na potrzeby nawigacji, chyba że tak jest w prototypie (suwak ma priorytet).

Parallel group D: Tasks 5.2, 5.3, 5.4, 5.5 są niezależne i mają rozłączne pliki. Wszystkie zależą od Task 5.1.

- [x] **Task 5.2: Ekran startowy i pusty folder.**
  - Strefa upuszczenia folderu z tekstem „Pliki JPG i ARW o tej samej nazwie pokażę jako jedno zdjęcie.”
  - Przycisk „Otwórz folder… ⌘O” otwierający `NSOpenPanel` (tylko foldery).
  - Lista „Ostatnie foldery” z `RecentFoldersStore`.
  - Ekran „Ten folder nie zawiera zdjęć” z przyciskiem „Otwórz inny folder…”.
  - **Files:** modify `PhotoSift/PhotoSift/Screens/StartScreen.swift` i `PhotoSift/PhotoSift/Screens/EmptyFolderScreen.swift` (created in Task 5.1), create `PhotoSift/PhotoSiftUITests/StartScreenUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/StartScreenUITests` przechodzi. Testy pokrywają: ekran startowy bez argumentu, ekran pustego folderu dla folderu bez JPG i ARW, obecność listy ostatnich folderów.

- [x] **Task 5.3: Widok pojedynczego zdjęcia.**
  - Podgląd na neutralnym ciemnoszarym tle.
  - Znaczniki na podglądzie: Ciemnia, edytowane, stan Albumu, RAW, blokada.
  - Zoom 100% w miejscu kursora: przytrzymanie Z albo przycisku myszy, z etykietą „100%”.
  - Pasek miniatur z pojedynczym zaznaczeniem i tymi samymi znacznikami.
  - Panel boczny:
    - nazwa pliku i typ,
    - aparat, obiektyw, ISO, przysłona, czas, ogniskowa, data,
    - sekcja „Stan”: Ciemnia, Edycja, Album/,
    - informacja dla zdjęcia tylko z RAW-em.
  - Ekran „Wszystkie zdjęcia przejrzane” z podsumowaniem i przyciskami.
  - Prefetch sąsiednich zdjęć przez `ImageLoader`.
  - W trybie edycji widok pokazuje `EditStage` zamiast podglądu, a panel boczny `EditPanel` zamiast sekcji „Stan”. Oba to zaślepki z Task 5.1.
  - **Files:** modify `PhotoSift/PhotoSift/Screens/SingleView/SinglePhotoView.swift` (created in Task 5.1), create `PhotoSift/PhotoSift/Screens/SingleView/PhotoStage.swift`, create `PhotoSift/PhotoSift/Screens/SingleView/Filmstrip.swift`, create `PhotoSift/PhotoSift/Screens/SingleView/InfoPanel.swift`, create `PhotoSift/PhotoSift/Screens/SingleView/ReviewDoneView.swift`, reuse `PhotoSift/PhotoSift/Common/StatusBadges.swift` (created in Task 5.1), reuse `PhotoSift/PhotoSift/Screens/Edit/EditPanel.swift` i `PhotoSift/PhotoSift/Screens/Edit/EditStage.swift` (created in Task 5.1), create `PhotoSift/PhotoSiftUITests/SingleViewUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/SingleViewUITests` przechodzi. Testy pokrywają:
      - metadane bieżącego zdjęcia z fikstury (ISO, przysłona, czas, obiektyw),
      - ⌫ usuwa i przechodzi dalej, a pliki znikają z folderu,
      - C oznacza i przechodzi dalej,
      - przytrzymanie Z pokazuje „100%”,
      - po ostatnim zdjęciu pojawia się „Wszystkie zdjęcia przejrzane”,
      - ⌘-klik w pasku miniatur nie zaznacza wielu zdjęć.

- [x] **Task 5.4: Siatka.**
  - Siatka miniatur z nazwą pliku i znacznikami.
  - Informacja o liczbie zdjęć i aktywnym filtrze, licznik zaznaczenia z przyciskiem „Odznacz”.
  - Zaznaczanie: ⌘-klik, ⇧-klik, ⌘A, Esc.
  - Strzałki w czterech kierunkach (↑ i ↓ według liczby kolumn).
  - Enter i dwuklik otwierają zdjęcie.
  - ⌫ i C działają na zaznaczone, a w panelu bocznym jest przycisk „Wklej balans bieli” dla zaznaczenia.
  - Komunikat dla pustego wyniku filtra.
  - **Files:** modify `PhotoSift/PhotoSift/Screens/Grid/GridView.swift` (created in Task 5.1), create `PhotoSift/PhotoSift/Screens/Grid/GridCell.swift`, create `PhotoSift/PhotoSift/Screens/Grid/GridSelectionPanel.swift`, reuse `PhotoSift/PhotoSift/Common/StatusBadges.swift` (created in Task 5.1), create `PhotoSift/PhotoSiftUITests/GridUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/GridUITests` przechodzi. Testy pokrywają: G przełącza widok, zaznaczenie 3 zdjęć ⌘-klikiem i ⌫ usuwa wszystkie 3, C oznacza wszystkie zaznaczone, Enter otwiera zdjęcie w widoku pojedynczym, ⌘2 filtruje Ciemnię.

- [x] **Task 5.5: Ściąga skrótów.** Nakładka „Skróty klawiszowe” otwierana przez ? i zamykana przez ? lub Esc. Grupy i skróty pochodzą z tabeli w `docs/workflow.md`, bez innych skrótów.
  - **Files:** modify `PhotoSift/PhotoSift/Screens/ShortcutsOverlay.swift` (created in Task 5.1), create `PhotoSift/PhotoSiftUITests/ShortcutsUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/ShortcutsUITests` przechodzi. Testy pokrywają: ? otwiera, Esc zamyka, obecność skrótów M, D i G.

### Faza 6: Edycja (UI)

**Goal:** Lekka obróbka JPEG-a z podglądem na żywo.
**Verification:** `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests`

Parallel group E: Tasks 6.1 i 6.2 są niezależne i mają rozłączne pliki. Oba zależą od Fazy 5.

- [x] **Task 6.1: Panel edycji.**
  - Zakładki „Światło i kolor (E)” i „Kadr (R)”.
  - Sekcja „Balans bieli”:
    - suwaki Temperatura i Tint (−100…100, dwuklik zeruje),
    - przyciski kopiuj i wklej balans bieli (⇧⌘C / ⇧⌘V).
  - Sekcja kadru:
    - przełącznik orientacji 3:2 / 2:3 (bez skrótu),
    - suwak „Kąt” (−45…45, krok 0,1, dwuklik zeruje).
  - Przycisk „Przed / po” (przytrzymanie, M) i „Resetuj ⇧⌘R”.
  - Wskaźnik „Zapisano”.
  - Stan zablokowany: „Edycja zablokowana”, a dla zdjęcia oznaczonego, ale nie wysłanego, przycisk „Usuń oznaczenie Ciemni”. Dla zdjęcia tylko z RAW-em: „Edycja niedostępna”.
  - D i Esc wracają do przeglądania.
  - **Files:** modify `PhotoSift/PhotoSift/Screens/Edit/EditPanel.swift` (created in Task 5.1), create `PhotoSift/PhotoSift/Screens/Edit/WhiteBalanceSection.swift`, create `PhotoSift/PhotoSift/Screens/Edit/CropSection.swift`, create `PhotoSift/PhotoSift/Screens/Edit/LockedEditPanel.swift`, create `PhotoSift/PhotoSiftUITests/EditPanelUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/EditPanelUITests` przechodzi. Testy pokrywają:
      - E otwiera panel,
      - zmiana temperatury zapisuje plik XMP z polem `photosift`,
      - D wraca do przeglądania,
      - panel zablokowany dla zdjęcia z Ciemni,
      - wklejenie balansu bieli na 3 zdjęcia zaznaczone w siatce oznacza je jako edytowane.

- [x] **Task 6.2: Kadrowanie i podgląd na żywo.**
  - Etap edycji renderuje podgląd przez `EditRenderer` na żywo, bez zauważalnych opóźnień przy przeciąganiu suwaków. Render działa na podglądzie w rozmiarze ekranu, nie na pełnej rozdzielczości.
  - Nakładka kadru:
    - zablokowana proporcja 3:2 lub 2:3,
    - przesuwanie i cztery uchwyty narożne,
    - siatka trójpodziału i etykieta wymiarów w pikselach,
    - ograniczenie przez `constrainCrop` przy obrocie.
  - Przytrzymanie M pokazuje obraz bez edycji z etykietą „Przed”.
  - Zoom 100% działa w zakładce „Światło i kolor”, a w zakładce „Kadr” nie.
  - **Files:** modify `PhotoSift/PhotoSift/Screens/Edit/EditStage.swift` (created in Task 5.1), create `PhotoSift/PhotoSift/Screens/Edit/CropOverlay.swift`, create `PhotoSift/PhotoSift/Screens/Edit/LivePreviewRenderer.swift`, create `PhotoSift/PhotoSiftUITests/CropUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/CropUITests` przechodzi. Testy pokrywają: R pokazuje nakładkę kadru, przeciągnięcie uchwytu zmienia etykietę wymiarów przy zachowanej proporcji 3:2, zmiana orientacji daje 2:3, przytrzymanie M pokazuje „Przed”.

### Faza 7: Ciemnia i eksport (UI)

**Goal:** Arkusze „Wyślij do Ciemni” i „Eksportuj” spinające operacje z Fazy 3.
**Verification:** `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests`

Parallel group F: Tasks 7.1 i 7.2 są niezależne i mają rozłączne pliki.

- [x] **Task 7.1: Arkusz „Wyślij do Ciemni”.**
  - Tekst: „N plików RAW zostanie przeniesionych do Ciemnia/ (razem z plikami XMP). Pliki JPEG zostają na miejscu.”
  - Lista plików `<id>.ARW + .xmp → Ciemnia/`.
  - Informacja: „Te zdjęcia nie trafią do eksportu z Photo Sift — gotowe pliki wyeksportujesz do Album/ z Lightrooma.”
  - Przyciski „Anuluj” i „Przenieś RAW-y” (Enter potwierdza, Esc anuluje).
  - Komunikat po zakończeniu, w tym o konfliktach.
  - **Files:** modify `PhotoSift/PhotoSift/Sheets/DarkroomSheet.swift` (created in Task 5.1), create `PhotoSift/PhotoSiftUITests/DarkroomSheetUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/DarkroomSheetUITests` przechodzi. Testy pokrywają: po potwierdzeniu ARW i XMP są w `Ciemnia/`, JPEG został na miejscu, licznik „Wyślij do Ciemni” spada do 0.

- [x] **Task 7.2: Arkusz „Eksportuj”.**
  - **Potwierdzenie:**
    - „N nowych, M do aktualizacji”,
    - „Pominięte: X w Ciemni, Y tylko RAW”, z informacją o konfliktach, jeśli są,
    - tekst „Eksport niczego z Album/ nie usuwa. Kopie zdjęć usuniętych lub wysłanych do Ciemni po wcześniejszym eksporcie usuń ręcznie w Finderze.”
  - **Postęp:** licznik, pasek i bieżący plik („Kopiuję / Renderuję / Aktualizuję …”) oraz przycisk „Zatrzymaj”.
  - **Zakończenie:** przyciski „Pokaż w Finderze” i „Gotowe”.
  - **Files:** modify `PhotoSift/PhotoSift/Sheets/ExportSheet.swift` (created in Task 5.1), create `PhotoSift/PhotoSiftUITests/ExportSheetUITests.swift`
  - **Definition of Done:**
    - [x] `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests/ExportSheetUITests` przechodzi. Testy pokrywają:
      - podsumowanie z poprawnymi liczbami dla fikstury,
      - po eksporcie `Album/` zawiera oczekiwane JPEG-i i nic poza nimi,
      - drugi eksport ma wyłączony przycisk (0 zmian),
      - zmiana edycji jednego zdjęcia daje „Eksportuj (1)”.

### Faza 8: Weryfikacja końcowa

Parallel group G: Tasks 8.1 i 8.2.

- [ ] **Task 8.1: Code review.** Przekaż `code-reviewer` ścieżkę planu i pełną listę zmienionych plików. Reviewer uruchamia `swift test --package-path Core` i build aplikacji, ocenia pokrycie testami oraz sprawdza zgodność z sekcjami „Do NOT touch / do NOT add” i „Security Considerations”. Testy UI i weryfikacja funkcjonalna działają w równoległym zadaniu 8.2, więc reviewer ich nie uruchamia.
  - **Files:** reuse wszystkich plików z Faz 1–7
  - **Definition of Done:**
    - [ ] Raport review bez otwartych uwag krytycznych

- [ ] **Task 8.2: Weryfikacja funkcjonalna.** Przekaż `feature-verifier` dokument `specifications/photo-sift-mvp/photo-sift-mvp.verification.md`.
  - **Files:** reuse `specifications/photo-sift-mvp/photo-sift-mvp.verification.md`
  - **Definition of Done:**
    - [ ] Wszystkie scenariusze z dokumentu weryfikacji przechodzą, z dowodami

### Faza 9: Poprawki po pierwszym przeglądzie aplikacji przez użytkownika (2026-11-25)

**Goal:** Wdrożyć uwagi użytkownika z pierwszego uruchomienia. Decyzje są zapisane w `docs/workflow.md`: sekcje „Przeglądanie”, „Lekka obróbka”, „Wygląd” i „Odrzucone”.
**Verification:** `swift test --package-path Core` oraz `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' build-for-testing`. Testy UI uruchamiamy dopiero w weryfikacji końcowej, gdy użytkownik nie korzysta z Maca.

- [x] **Task 9.1: Ekspozycja i zachowanie decyzji (Core).**
  - `EditParams.exposure` (EV): wchodzi do `isIdentity` i `fingerprint`. Brak pola w starym XMP oznacza 0, a nie brak edycji.
  - Zapis w XMP jako `photosift:exposure`.
  - `EditRenderer`: `CIExposureAdjust` w tym samym potoku.
  - `toggleDarkroom` nie przechodzi do następnego zdjęcia.
  - Usunięcie stanu „wszystko przejrzane”: → na ostatnim zdjęciu nic nie robi.
  - Kopiowanie i wklejanie balansu bieli dalej dotyczy tylko temperatury i tintu.
- [x] **Task 9.2: Poprawki interfejsu (aplikacja).**
  - Suwak ekspozycji.
  - Przed/po wyłącza tylko temperaturę, tint i ekspozycję.
  - Bez wskaźnika „Zapisano”, bez linii pod suwakami, bez obwódek przycisków i kafli.
  - Napis „Eksportuj” wyśrodkowany w pionie.
  - Miniatury w pasku wypełniają kafel, a pionowe zdjęcia mają pionowe kafle.
  - Usunięcie ekranu „Wszystkie zdjęcia przejrzane”.
  - „Wyślij do Ciemni” przemianowane na „Do Ciemni”.
  - Testy UI dostosowane do nowego zachowania.

## Security Considerations

Aplikacja działa bez sandboxa na prawdziwych zdjęciach użytkownika, więc najważniejsze jest bezpieczeństwo plików:

- Żadna ścieżka kodu nie wywołuje `FileManager.removeItem` na plikach użytkownika. Usuwanie odbywa się wyłącznie przez `trashItem`. Wyjątek: pliki tymczasowe tworzone przez samą aplikację.
- Oryginalne JPEG-i i ARW-y są tylko odczytywane, przenoszone do Kosza albo przenoszone do `Ciemnia/`, nigdy zapisywane.
- Zapis do `Album/` i plików XMP jest atomowy. Przerwany zapis nie zostawia uszkodzonego pliku.
- Każda operacja zapisu sprawdza, że ścieżka docelowa leży w otwartym folderze sesji lub jego podfolderach `Ciemnia/` i `Album/`.
- Pliki obce w `Album/` (`conflict`) nie są nadpisywane ani usuwane.

## Acceptance Criteria

- [ ] Para JPEG + ARW to jedna pozycja. Podgląd pochodzi z JPEG-a, a zdjęcie tylko z RAW-em z miniatury osadzonej.
- [ ] Przy zdjęciu widać aparat, obiektyw, ISO, przysłonę, czas, ogniskową i datę.
- [ ] ⌫ od razu przenosi do Kosza JPEG, ARW i XMP i przechodzi dalej, nie ruszając `Album/`.
- [ ] C przełącza Ciemnię i przechodzi dalej. Zdjęcie oznaczone ma zablokowaną edycję.
- [ ] Kadr 3:2 lub 2:3, prostowanie, temperatura i tint zapisują się automatycznie w XMP i przetrwają ponowne uruchomienie.
- [ ] Balans bieli można skopiować i wkleić na zdjęcia zaznaczone w siatce.
- [ ] „Wyślij do Ciemni” przenosi tylko ARW i XMP do `Ciemnia/`, czyszcząc pola `photosift`.
- [ ] „Eksportuj” zapisuje do `Album/` tylko JPEG-i: kopie 1:1 zdjęć bez edycji i rendery z EXIF-em zdjęć z edycją, z pominięciem Ciemni i zdjęć tylko z RAW-em.
- [ ] Ponowny eksport dodaje i aktualizuje, nigdy nie usuwa i nigdy nie dotyka plików obcych.
- [ ] Oryginalne pliki nigdy nie są modyfikowane.
- [ ] Wszystkie skróty z `docs/workflow.md` działają, a ściąga je pokazuje.
- [ ] Aplikacja pamięta ostatnie zdjęcie w folderze i listę ostatnich folderów.

## Improvements (Out of Scope)

- Porównanie dwóch zdjęć obok siebie z synchronizowanym zoomem.
- Pomiar wydajności na dużych folderach (np. 1000+ zdjęć) i ewentualna optymalizacja skanowania.
- Ikona aplikacji i podpisanie (notaryzacja), jeśli aplikacja ma działać na innym komputerze.
- CI uruchamiające testy Core.
- Niestabilny test `SessionEditTests.updateEditSavesToXMPAfterDelay`: pod obciążeniem raz na kilka przebiegów zapis nie zdąży przed sprawdzeniem (opóźnienie 50 ms, oczekiwanie 400 ms).