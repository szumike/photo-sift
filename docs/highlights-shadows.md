# Światła i Cienie: notatki z eksperymentów

Stan na 2026-11-26. Kod eksperymentu jest na gałęzi `experiment/exposure-fusion`, a nie na `main`.

## Wynik

Na gałęzi `experiment/exposure-fusion` jest fuzja syntetycznych ekspozycji. Ocena po teście na prawdziwych zdjęciach:

- **Cienie** działają zadowalająco.
- **Światła** po poprawce (zachowanie i wzmocnienie drobnego detalu) są lepsze, ale jeszcze nie idealne.

Ograniczenie JPEG-a: przepalonego nieba (255) nie da się odzyskać żadnym algorytmem, bo detalu nie ma w pliku. Pomaga tylko w niebie bardzo jasnym, ale nie przepalonym.

## Podejścia, które już sprawdziliśmy

| Podejście | Gdzie | Wynik |
|---|---|---|
| Lokalna tonacja z filtrem prowadzonym (guided filter) | commit `41b866b` (WIP) | odrzucone |
| Wbudowany `CIHighlightShadowAdjust` + krzywa tonalna dla świateł na plus | commit `9eb4d90`, obecnie na `main`, suwaki ukryte | odrzucone, za słabe |
| Fuzja syntetycznych ekspozycji (Mertens) | gałąź `experiment/exposure-fusion` | cienie OK, światła prawie |

## Jak działa fuzja ekspozycji (gałąź eksperymentu)

Kod: `Core/Sources/PhotoSiftCore/Rendering/ExposureFusion.swift`, stałe w `EditRenderer.HighlightsShadows`.

1. Trzy wersje zdjęcia: oryginał, wersja przesunięta suwakiem Cienie (do ±3 EV), wersja przesunięta suwakiem Światła (do ±1,5 EV). Rozjaśnione wersje są miękko obcinane przy bieli.
2. Wagi z jasności oryginału: ciemne partie biorą wersję „cieni”, jasne wersję „świateł”, reszta oryginał.
3. Mieszanie piramidami Laplace'a (wiele skal), w skali gamma 2.2. Duże obszary zmieniają się jako całość, drobny detal zostaje.
4. Światła: drobne poziomy piramidy dostają z powrotem kontrast detalu, który ciemniejsza wersja traci, a przy wartościach ujemnych dodatkowo +40% (`highlightDetailBoost`). Wzmacniane są tylko małe różnice (`detailEdge`), dzięki czemu na horyzoncie nie powstaje jasna obwódka.

Bez nowych zależności. Kernele w Core Image Kernel Language: przestarzałe API, ale działa i nie wymaga narzędzi Metal. Podgląd 2000 px liczy się w około 15 ms.

## Źródła i biblioteki

Gotowej biblioteki dla Swift/Core Image nie ma. Algorytmy przepisujemy sami, a cudzy kod służy za wzór.

- **Local Laplacian Filter** (Paris, Hasinoff, Kautz 2011; szybka wersja: Aubry i in. 2014, [PDF](https://jankautz.com/publications/FastLLF_TOG14.pdf)). Wzór: Halide `apps/local_laplacian` (MIT), darktable moduł „local contrast” (GPL, [opis](https://www.darktable.org/2017/11/local-laplacian-pyramids/)).
- **Exposure fusion** (Mertens, Kautz, Van Reeth 2007). Wzór: OpenCV `MergeMertens` (Apache 2.0).
- **darktable tone equalizer** (filtr prowadzony „eigf”, [opis](https://www.darktable.org/usermanual/en/module-reference/processing-modules/tone-equalizer/)). GPL.
- Kodu z darktable i RawTherapee nie kopiujemy (GPL). Wolno brać idee, wzory i domyślne parametry.
- Adobe nie publikuje algorytmu suwaków Highlights/Shadows (od Process Version 2012). Twierdzenie, że to Local Laplacian, jest niepotwierdzone.

## Następne kroki (gdy wrócimy do tematu)

1. **Dostrojenie do Lightrooma zamiast na oko.** Przygotować około 5 różnych JPEG-ów (niebo, pod światło, ciemne wnętrze) i wyeksportować je z Lightrooma z ustawieniami: Światła −50 i −100, Cienie +50 i +100, pozostałe suwaki na 0. Skrypt dobierze stałe z `EditRenderer.HighlightsShadows` tak, żeby wynik był jak najbliższy Lightroomowi.
2. **Opcjonalnie Local Laplacian.** Około 8 przemapowanych kopii zamiast 3. Używa tych samych piramid co obecny kod. Około 2,5–3× wolniejszy (podgląd ~40–50 ms). Ryzyko: pamięć przy eksporcie 24 Mpx. Daje przy okazji suwak „Klarowność”. Warto po kroku 1 porównać obie metody z Lightroomem.
3. Po akceptacji: scalić gałąź do `main`, dopisać testy regresji dla nowych zachowań i uruchomić testy UI.
