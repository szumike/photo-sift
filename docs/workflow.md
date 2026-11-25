# Workflow Photo Sift

Photo Sift służy do szybkiej selekcji zdjęć z Sony A7 III (JPEG + ARW) na MacBooku. Przeglądam JPEG-i i usuwam słabe ujęcia. RAW-y zdjęć do mocnej obróbki wysyłam do „Ciemni”, czyli folderu dla Lightrooma. Pozostałe zdjęcia, po ewentualnej lekkiej poprawce, eksportuję do folderu z gotowymi zdjęciami. Oryginały nigdy nie są modyfikowane.

## Proces krok po kroku

1. Wrzucam do folderu wszystkie zdjęcia z sesji, JPEG i ARW razem.
2. Otwieram folder w Photo Sift. Naraz oglądam tylko jeden folder.
3. Usuwam słabe zdjęcia: duplikaty, nieostre.
4. Zdjęcia do lekkiej obróbki poprawiam: kadr, prostowanie, balans bieli.
5. Zdjęcia do mocnej obróbki oznaczam jako **Ciemnia**.
6. Klikam **Do Ciemni**: oznaczone RAW-y trafiają do `Ciemnia/`.
7. Klikam **Eksportuj**: pozostawione zdjęcia trafiają do `Album/`.
8. Na folderze `Ciemnia/` uruchamiam Lightrooma i eksportuję z niego gotowe zdjęcia do `Album/`, z oryginalnymi nazwami plików.

## Para JPEG + ARW to jedno zdjęcie

Pliki o tej samej nazwie bazowej (`DSC01234.JPG` i `DSC01234.ARW`) aplikacja pokazuje jako jedną pozycję.

- Podgląd zawsze pochodzi z JPEG-a. RAW jest dekodowany tylko na czas przytrzymania B (podgląd RAW).
- Plik ARW bez pary JPEG pokazuję z podglądu osadzonego w pliku RAW. Takiego zdjęcia nie da się edytować i nie trafia do eksportu. Można je usunąć albo wysłać do Ciemni.
- Jedyne decyzje o zdjęciu to **usuń** i **Ciemnia**. Nie ma ocen, gwiazdek ani etykiet.
- ARW-y zdjęć zostawionych jako JPEG zostają w folderze sesji. Aplikacja nic z nimi nie robi.

## Przeglądanie

- **Metadane przy każdym zdjęciu:** model aparatu, obiektyw, ISO, przysłona (f), czas naświetlania, ogniskowa, data wykonania.
- **Zoom** w miejscu kursora, do oceny ostrości: przytrzymanie Z albo przytrzymanie przycisku myszy na zdjęciu. Poziom powiększenia (100 / 150 / 200 / 300%, domyślnie 100%) wybiera się w oknie Ustawienia (⌘,); aplikacja go pamięta.
- **Przed/po:** przytrzymanie M pokazuje zdjęcie bez zmian światła i koloru (temperatura, tint, ekspozycja). Kadr i prostowanie zostają widoczne.
- **Podgląd RAW:** przytrzymanie B pokazuje prawdziwe wywołanie pliku ARW (bez edycji Photo Sift), do porównania z JPEG-iem. Zdjęcie bez RAW-a pokazuje „Brak RAW”.
- **Pamiętanie pozycji:** po ponownym otwarciu folderu wracam do zdjęcia, na którym skończyłem.
- **Filtry:** wszystkie, Ciemnia, edytowane.
- **Siatka wszystkich zdjęć:** widok miniatur całego folderu. G przełącza siatkę ↔ pojedyncze zdjęcie, a Enter lub dwuklik otwiera zdjęcie z siatki. W siatce ⌫ i C działają na wszystkie zaznaczone zdjęcia.
- **Zaznaczanie wielu zdjęć tylko w siatce.** Pasek miniatur w widoku pojedynczym zawsze wskazuje jedno zdjęcie.
- **Obsługa klawiaturą:** wszystkie decyzje bez myszy. Po usunięciu (⌫) aplikacja przechodzi do następnego zdjęcia. Oznaczenie Ciemni (C lub przycisk) zostaje na bieżącym zdjęciu.
- **Koniec folderu:** → na ostatnim zdjęciu nic nie robi. Nie ma ekranu podsumowania.

## Skróty klawiszowe

| Akcja | Skrót |
| --- | --- |
| Następne / poprzednie zdjęcie | → / ← |
| Siatka ↔ pojedyncze zdjęcie | G |
| Otwórz zdjęcie z siatki | Enter / dwuklik |
| Usuń | ⌫ |
| Ciemnia (przełącz) | C |
| Zoom (poziom z Ustawień) | przytrzymaj Z |
| Przed/po | przytrzymaj M |
| Podgląd RAW | przytrzymaj B |
| Edycja: światło i kolor | E |
| Edycja: kadr i prostowanie | R |
| Powrót z edycji do przeglądania | D (w narzędziu Kadr także Enter) |
| Kopiuj / wklej balans bieli | ⇧⌘C / ⇧⌘V |
| Resetuj edycję | ⇧⌘R |
| Cofnij / ponów edycję | ⌘Z / ⇧⌘Z |
| Wyjście z edycji / wyczyszczenie zaznaczenia | Esc |
| Filtry: Wszystkie / Ciemnia / Edytowane | ⌘1 / ⌘2 / ⌘3 |
| Zaznacz wszystkie (siatka) | ⌘A |
| Poruszanie się po siatce | ← ↑ ↓ → |
| Otwórz folder | ⌘O |
| Ustawienia | ⌘, |
| Ściąga skrótów | ? |

Zmiana orientacji kadru nie ma skrótu, tylko przycisk.

Przytrzymanie ⌫ lub C nie powtarza akcji: jedno naciśnięcie to jedna decyzja.

## Usuwanie działa od razu

Usunięcie natychmiast przenosi do Kosza cały komplet: JPEG, ARW i XMP. Nie dotyka `Album/`. Nie ma okna potwierdzenia ani Cofnij w aplikacji. Pomyłkę naprawiam w Koszu Findera („Odłóż z powrotem”).

## Lekka obróbka

| Edycja | Status |
| --- | --- |
| Kadrowanie w proporcjach oryginału (3:2) | MVP |
| Przełącznik orientacji kadru pion/poziom (3:2 ↔ 2:3) | MVP |
| Prostowanie (obrót o kąt) | MVP |
| Balans bieli: temperatura i tint | MVP |
| Kopiowanie balansu bieli na zaznaczone zdjęcia | MVP |
| Ekspozycja | MVP |
| Światła i Cienie (highlights / shadows) | zaimplementowane prostym filtrem macOS, **ukryte w interfejsie** (na przyszłość) |

- Edycje to parametry zapisane w pliku XMP. Oryginalny JPEG nigdy nie jest zmieniany.
- Edycje zostają po eksporcie, więc każdą można później zmienić i wyeksportować ponownie.
- Zdjęć oznaczonych jako Ciemnia nie da się edytować.
- ⌘Z cofa, a ⇧⌘Z ponawia edycje bieżącego zdjęcia: suwaki, kadr, kąt, orientację, reset i wklejenie balansu bieli. Krok powstaje dopiero po puszczeniu myszy: całe przeciągnięcie suwaka lub kadru, od wciśnięcia do puszczenia, to jeden krok. Historia jest osobna dla każdego zdjęcia i trwa do zamknięcia folderu. Tylko skróty, bez przycisków. Usuwania, oznaczenia Ciemni, wysyłki do Ciemni i eksportu nie da się cofnąć.
- Panel edycji nie pokazuje wskaźnika „Zapisano”: zapis jest automatyczny i nie wymaga uwagi.

## Ciemnia: do Lightrooma idzie tylko RAW

- Oznaczenie „Ciemnia” niczego od razu nie przenosi.
- Zdjęcia bez pliku RAW (sam JPEG) nie da się oznaczyć jako Ciemnia. Aplikacja pokazuje komunikat „Brak pliku RAW — nie można wysłać do Ciemni”.
- Przycisk **Do Ciemni** przenosi oznaczone `DSC01234.ARW` razem z ich `DSC01234.xmp` do podfolderu `Ciemnia/`.
- JPEG zostaje w folderze głównym.

## Eksport: gotowe zdjęcia w folderze `Album/`

Przycisk **Eksportuj** zapisuje do podfolderu `Album/` wszystkie pozostawione zdjęcia, z wyjątkiem oznaczonych jako Ciemnia:

- zdjęcia bez edycji są kopiowane 1:1, bez ponownej kompresji. Na dysku APFS taka kopia nie zajmuje dodatkowego miejsca,
- zdjęcia z edycjami są renderowane do JPEG-a (jakość ok. 95%) z zachowanym EXIF-em (aparat, obiektyw, ISO, przysłona, czas, data, GPS).

Do `Album/` Lightroom eksportuje też zdjęcia obrobione w Ciemni. Zdjęcia z Ciemni są pomijane w eksporcie z Photo Sift, żeby oryginalny JPEG z aparatu nie zderzył się z plikiem z Lightrooma o tej samej nazwie.

W `Album/` są wyłącznie pliki JPEG: bez plików XMP i bez ukrytych plików Photo Sift.

### Album zmienia się tylko przy eksporcie, a eksport tylko dodaje i aktualizuje

- Poza kliknięciem „Eksportuj” Photo Sift nigdy nie zmienia `Album/`.
- „Eksportuj” dodaje nowe pozostawione zdjęcia i renderuje ponownie zdjęcia ze zmienionymi edycjami. Niezmienionych nie rusza.
- Eksport niczego z `Album/` nie usuwa. Kopia zdjęcia usuniętego lub wysłanego do Ciemni po wcześniejszym eksporcie zostaje w `Album/`, a usuwam ją ręcznie w Finderze.
- Photo Sift rozpoznaje swoje pliki po ich zawartości, bez listy eksportów:
  - kopia bez edycji jest identyczna z oryginałem,
  - plik z edycjami ma w metadanych osadzonych w samym JPEG-u znacznik Photo Sift i odcisk parametrów edycji, po którym widać, czy jest aktualny.
- Każdy inny plik w `Album/`, np. z Lightrooma, jest obcy i nigdy nie jest zmieniany ani usuwany.
- Wysłanie do Ciemni usuwa pola Photo Sift z XMP RAW-a, żeby nie przeszły do eksportu z Lightrooma.
- `Album/` zarządza Photo Sift: zdjęcie usunięte z `Album/` w Finderze wróci przy następnym eksporcie.

## Edycje i oznaczenia trzymamy w plikach XMP

Para JPEG + ARW ma wspólny plik `DSC01234.xmp`, a Lightroom czyta go jako plik towarzyszący ARW-a.

- Edycje i oznaczenie Ciemni trafiają do własnej przestrzeni nazw Photo Sift, a nie do pól Adobe (`crs:`). Inaczej Lightroom nałożyłby kadr z JPEG-a na RAW-a.
- Edycje są zapisywane w XMP od razu, więc nic nie ginie przy zamknięciu aplikacji.

## Wygląd

- Przyciski i kafle bez obwódek: rozróżnia je tylko tło.
- Suwaki bez dodatkowych linii czy znaczników pod spodem.
- Dolny kafel panelu bocznego sięga do dołu okna, jak w prototypie.
- Suwak ma fokus klawiatury: strzałki ↑/↓ zmieniają ekspozycję o 0,1 EV, a pozostałe suwaki o 5.
- Suwaki temperatury, tintu i ekspozycji wyglądają jak w prototypie: cienki tor z gradientem (temperatura niebieski → szary → pomarańczowy, tint zielony → szary → magenta, ekspozycja czarny → szary → biały) i jasny okrągły uchwyt.
- Ikona aplikacji: wersja „1f · Czerwień” z designu (`docs/design/app-icon-1f.svg`).
- Nagłówek siatki („4 zdjęcia”, „4 zaznaczone”) bez linii pod spodem.
- Pasek miniatur pod zdjęciem można schować i pokazać przyciskiem na samym pasku. Aplikacja pamięta ten wybór między uruchomieniami.
- Miniatury w pasku pod zdjęciem wypełniają kafel (bez czarnych pasów), a zdjęcia pionowe mają pionowy kafel.

## Na później

- Porównanie dwóch zdjęć obok siebie z synchronizowanym zoomem.

## Odrzucone

- Cofnij (⌘Z) dla usuwania.
- Pipeta do balansu bieli.
- Inne proporcje kadru niż oryginalne.
- Oceny i etykiety.
- Usuwanie RAW-ów zdjęć zostawionych jako JPEG.
- Ekran „Wszystkie zdjęcia przejrzane”.
- Wskaźnik „Zapisano” w panelu edycji.
