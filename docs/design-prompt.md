Zaprojektuj klikalny prototyp natywnej aplikacji na macOS o nazwie **Photo Sift**: narzędzia do szybkiej selekcji zdjęć po sesji fotograficznej. Interfejs po polsku. Ekran docelowy: MacBook Pro 14" (1512×982 pt). Styl zgodny z Human Interface Guidelines i aktualnym wyglądem macOS: systemowe kontrolki, pasek narzędzi, panele boczne. Bez własnego „brandingu”.

## Dla kogo i po co

Fotograf amator fotografuje Sony A7 III w trybie JPEG + RAW (ARW). Po sesji ma w folderze kilkaset par plików. Jego MacBook nie radzi sobie z szybkim wyświetlaniem RAW-ów, więc w Photo Sift przegląda JPEG-i i podejmuje o każdym zdjęciu jedną z decyzji:

- **usuń**: słabe ujęcie, duplikat, nieostre. Trafia od razu do Kosza,
- **Ciemnia**: zdjęcie do mocnej obróbki w Lightroomie. Jego RAW zostanie przeniesiony do podfolderu `Ciemnia/`,
- **zostaw**: brak decyzji to decyzja. Zdjęcie może dostać lekką poprawkę i trafi do `Album/`.

Najważniejsze jest tempo: selekcja ma iść klawiaturą, bez myszy, z automatycznym przejściem do następnego zdjęcia po decyzji.

## Ekrany i stany do zaprojektowania

1. **Start (brak otwartego folderu).** Przycisk „Otwórz folder”, lista ostatnich folderów, możliwość upuszczenia folderu na okno.

2. **Przeglądanie (główny ekran).**
   - Duży podgląd bieżącego zdjęcia na neutralnym, ciemnoszarym tle, które nie zaburza oceny kolorów.
   - Pasek miniatur (filmstrip) z zaznaczonym bieżącym zdjęciem.
   - Panel metadanych: model aparatu, obiektyw, ISO, przysłona (f), czas naświetlania. Przykład: Sony ILCE-7M3, FE 24-70mm F2.8 GM, ISO 400, f/4, 1/250 s.
   - Pozycja w folderze, np. „124 / 512”.
   - Filtry: Wszystkie / Ciemnia / Edytowane.
   - Znaczniki na miniaturach i przy podglądzie: oznaczone do Ciemni, edytowane, stan eksportu (w Albumie i aktualne / zmienione od eksportu / jeszcze nie wyeksportowane).
   - W pasku narzędzi dwa przyciski akcji z licznikami: **Wyślij do Ciemni (5)** i **Eksportuj (14)**.

3. **Zoom 100%.** Po przytrzymaniu klawisza podgląd powiększa się do 100% w miejscu kursora, żeby ocenić ostrość.

4. **Tryb edycji (lekka obróbka JPEG-a).**
   - Nakładka kadrowania z zablokowanymi proporcjami oryginału (3:2) i siatką trójpodziału.
   - Jeden przycisk zmiany orientacji kadru: poziom ↔ pion (3:2 ↔ 2:3).
   - Suwak prostowania (kąt obrotu).
   - Suwaki balansu bieli: temperatura i tint.
   - Akcje „Kopiuj balans bieli” i „Wklej balans bieli” na zaznaczone zdjęcia, np. na całą serię z tym samym światłem.
   - Przytrzymanie klawisza pokazuje zdjęcie przed edycją (przed/po).
   - Reset edycji.
   - Edycje są zapisywane od razu i nie ma przycisku „Zapisz”.

5. **Zdjęcie oznaczone jako Ciemnia w trybie edycji.** Edycja jest zablokowana, z czytelnym wyjaśnieniem dlaczego.

6. **Zaznaczanie wielu zdjęć** w pasku miniatur, np. do wklejenia balansu bieli.

7. **Arkusz „Wyślij do Ciemni”.** Podsumowanie przed wykonaniem: „5 plików RAW zostanie przeniesionych do Ciemnia/. Pliki JPEG zostają na miejscu.”

8. **Arkusz „Eksportuj”.** Podsumowanie przed wykonaniem: „12 nowych, 2 do aktualizacji”. Informacja, że eksport niczego z `Album/` nie usuwa. Do tego stan postępu eksportu.

9. **Stany brzegowe:**
   - zdjęcie, które ma tylko plik RAW bez JPEG-a (podgląd z miniatury osadzonej w RAW-ie, z dyskretnym oznaczeniem),
   - pusty folder,
   - wszystkie zdjęcia przejrzane.

10. **Ściąga skrótów klawiszowych** jako nakładka. Skróty nie są jeszcze ustalone, więc zaproponuj zestaw dla: następne/poprzednie zdjęcie, usuń, Ciemnia (przełącz), zoom 100%, przed/po, tryb edycji, kopiuj/wklej balans bieli, zmiana orientacji kadru.

## Poza zakresem (nie projektuj)

- oceny, gwiazdki, kolorowe etykiety,
- porównywanie dwóch zdjęć obok siebie,
- pipeta do balansu bieli,
- inne proporcje kadru niż oryginalne,
- cofanie usunięcia w aplikacji,
- ekspozycja i inne narzędzia edycji.

## Czego oczekuję

Klikalny prototyp, w którym da się przejść główny przepływ: otwarcie folderu → przeglądanie i decyzje → edycja zdjęcia → wysłanie do Ciemni → eksport. Zamiast prawdziwych zdjęć mogą być zastępcze obrazy krajobrazów i portretów w proporcjach 3:2 i 2:3.
