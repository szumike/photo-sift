# Photo Sift MVP: weryfikacja

Plan: `specifications/photo-sift-mvp/photo-sift-mvp.plan.md`
Wymagania: `docs/workflow.md`
Aplikacja: Photo Sift, natywna aplikacja macOS (bez serwera i bazy danych)

## Environment

- Komendy uruchamiane z głównego folderu repozytorium.
- Build: `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' -derivedDataPath build build`, wynik w `build/Build/Products/Debug/PhotoSift.app`.
- Uruchomienie: `open -n build/Build/Products/Debug/PhotoSift.app --args --open-folder $HOME/photo-sift-verify/sesja`.
- Sterowanie klawiaturą: `osascript -e 'tell application "System Events" to key code <kod>'` (wymaga zgody Accessibility dla terminala).
- Zrzuty ekranu: `screencapture -x <plik>.png`. Każdy zrzut jest **oglądany i opisany** w raporcie.

## Seeding

Pracuj wyłącznie na kopii. Folder `assets/` zawiera prawdziwe zdjęcia użytkownika i nie może się zmienić.

```
rm -rf $HOME/photo-sift-verify && mkdir -p $HOME/photo-sift-verify/sesja
cp assets/*.JPG assets/*.ARW $HOME/photo-sift-verify/sesja/
mdimport $HOME/photo-sift-verify/sesja
shasum -a 256 $HOME/photo-sift-verify/sesja/* > $HOME/photo-sift-verify/przed.sha
```

`mdls` czyta EXIF z indeksu Spotlight, dlatego kopia leży w folderze domowym (`/tmp` nie jest indeksowany). Przed każdym `mdls` na nowo powstałym pliku (np. w `Album/`) uruchom `mdimport <plik>`.

Oczekiwany stan: 8 plików, 4 pary z A7 III. Kolejność według daty wykonania:

| # | Zdjęcie | Rola w scenariuszach |
| --- | --- | --- |
| 1 | DSC01906 | usuwane |
| 2 | DSC02181 | Ciemnia |
| 3 | DSC02416 | edytowane |
| 4 | DSC02418 | bez edycji |

## Scenarios

### 0. [UITEST] Pełny zestaw testów UI

- Uruchom `xcodebuild -project PhotoSift/PhotoSift.xcodeproj -scheme PhotoSift -destination 'platform=macOS' test -only-testing:PhotoSiftUITests`.
- Oczekiwane: wszystkie testy przechodzą.
- Dowód: podsumowanie wyniku komendy.

### 1. [APP][FS] Metadane i usuwanie na prawdziwych plikach

- Uruchom aplikację na kopii folderu.
- Zrzut 1: DSC01906 z panelem metadanych. Oczekiwane wartości:
  - aparat: ILCE-7M3,
  - obiektyw: Sony E 50mm F2.0,
  - zgodność ISO, przysłony i czasu z `mdls -name kMDItemISOSpeed -name kMDItemFNumber -name kMDItemExposureTimeSeconds $HOME/photo-sift-verify/sesja/DSC01906.JPG`.
- Przytrzymaj Z (`osascript -e 'tell application "System Events" to key down "z"'`, zrzut, potem `key up "z"`). Oczekiwane: podgląd w 100% z etykietą „100%”, a po puszczeniu powrót do widoku całości. Testy UI tego nie pokrywają, bo XCUITest nie potrafi przytrzymać klawisza.
- Naciśnij ⌫.
- Oczekiwane:
  - w folderze nie ma już `DSC01906.JPG` ani `DSC01906.ARW`,
  - aplikacja pokazuje DSC02181 i komunikat „DSC01906 w Koszu”.
- Dowód: zrzuty przed i po oraz `ls $HOME/photo-sift-verify/sesja`.

### 2. [APP][FS] Ciemnia

- Na DSC02181 naciśnij C. Sprawdź, że powstał `DSC02181.xmp` z polem `photosift`.
- Kliknij „Wyślij do Ciemni” i potwierdź.
- Oczekiwane:
  - `Ciemnia/DSC02181.ARW` i `Ciemnia/DSC02181.xmp` istnieją,
  - `DSC02181.JPG` został w folderze głównym,
  - `grep -c photosift Ciemnia/DSC02181.xmp` zwraca 0.
- Dowód: zrzut arkusza przed potwierdzeniem i wyniki komend.

### 3. [APP][FS] Edycja i eksport

- Na DSC02416 zmniejsz kadr (R) i zmień temperaturę (E). DSC02418 zostaw bez zmian. Kliknij „Eksportuj” i potwierdź.
- Oczekiwane:
  - `ls Album/` pokazuje wyłącznie `DSC02416.JPG` i `DSC02418.JPG`, bez DSC02181,
  - `cmp DSC02418.JPG Album/DSC02418.JPG` nie zgłasza różnic,
  - `sips -g pixelWidth -g pixelHeight Album/DSC02416.JPG` pokazuje wymiary mniejsze niż 3936×2624 w proporcji 3:2,
  - `mdls -name kMDItemFNumber -name kMDItemAcquisitionModel Album/DSC02416.JPG` zwraca wartości oryginału.
- Dowód: zrzut arkusza eksportu z liczbami („2 nowe”, pominięte: 1 w Ciemni), wyniki komend oraz zrzut podglądu DSC02416 przed i po (przytrzymanie M).

### 4. [APP][FS] Ponowny eksport i plik obcy

- Podmień kopię DSC02418 w Albumie na plik obcy:

  ```
  sips -r 90 $HOME/photo-sift-verify/sesja/DSC02418.JPG --out $HOME/photo-sift-verify/obcy.jpg
  cp $HOME/photo-sift-verify/obcy.jpg $HOME/photo-sift-verify/sesja/Album/DSC02418.JPG
  shasum -a 256 $HOME/photo-sift-verify/sesja/Album/DSC02418.JPG
  ```

- W aplikacji zmień temperaturę DSC02416 jeszcze raz, otwórz „Eksportuj” i potwierdź.
- Oczekiwane:
  - arkusz pokazuje „1 do aktualizacji” i konflikt dla DSC02418,
  - po eksporcie suma `Album/DSC02418.JPG` jest bez zmian,
  - `Album/DSC02416.JPG` ma nową sumę.
- Dowód: zrzut arkusza oraz sumy przed i po.

### 5. [FS] Oryginały nietknięte

- Uruchom `shasum -a 256 -c $HOME/photo-sift-verify/przed.sha`.
- Oczekiwane: zgodne sumy dla wszystkich plików obecnych w folderze. Brakują wyłącznie `DSC01906.JPG`, `DSC01906.ARW` (Kosz) i `DSC02181.ARW` (Ciemnia).
- Dowód: wynik komendy.
- Dodatkowo `shasum -a 256 assets/*` porównane z sumami z kopii potwierdza, że `assets/` się nie zmienił.

### 6. [MANUAL] Zgodność z Lightroomem (wykonuje użytkownik)

- Zaimportuj `Ciemnia/` do Lightrooma.
- Oczekiwane: DSC02181.ARW otwiera się bez kadru i bez zmian balansu bieli z Photo Sift.
- Wyeksportuj go z Lightrooma do `Album/` z oryginalną nazwą.
- Oczekiwane: kolejny eksport z Photo Sift nie dotyka tego pliku.
- Dowód: potwierdzenie użytkownika.

## Pass criteria

Każdy scenariusz przechodzi z dowodami. Raport zawiera wynik każdego scenariusza (pass/fail) z dowodami, a na końcu listę blokerów. Czysty przebieg jest stwierdzony wprost.

## Boundaries

- Nigdy nie poprawiaj kodu.
- Pracuj wyłącznie na kopii w `$HOME/photo-sift-verify/`. Nigdy nie modyfikuj `assets/`.
- Nie opróżniaj Kosza.
- Przy brakującym warunku wstępnym (np. brak zgody Accessibility) zatrzymaj się i zgłoś, zamiast improwizować.
