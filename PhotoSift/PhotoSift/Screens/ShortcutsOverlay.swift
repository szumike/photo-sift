import SwiftUI

/// "Skróty klawiszowe" cheat sheet. Open/close keys are handled by `KeyboardRouter`; a click on the dim area closes it.
/// Shortcuts come only from the table in `docs/workflow.md`.
/// Identifiers: `overlay.shortcuts`, `shortcut.<keys>` per row (e.g. `shortcut.G`, `shortcut.M`, `shortcut.D`).
struct ShortcutsOverlay: View {
    @Environment(AppModel.self) private var model

    private struct Shortcut: Identifiable {
        let label: String
        let keys: [String]
        var id: String { keys.joined() }
    }

    private struct Group: Identifiable {
        let title: String
        let items: [Shortcut]
        var id: String { title }
    }

    private static let groups: [Group] = [
        Group(title: "Nawigacja", items: [
            Shortcut(label: "Następne / poprzednie zdjęcie", keys: ["→", "←"]),
            Shortcut(label: "Siatka ↔ pojedyncze zdjęcie", keys: ["G"]),
            Shortcut(label: "Tylko zdjęcie, pełny ekran (Esc wychodzi)", keys: ["F"]),
            Shortcut(label: "Pełny ekran okna", keys: ["⌃⌘F"]),
            Shortcut(label: "Otwórz zdjęcie z siatki", keys: ["Enter", "dwuklik"]),
            Shortcut(label: "Filtry: Wszystkie / Ciemnia / Edytowane / Do usunięcia", keys: ["⌘1", "⌘2", "⌘3", "⌘4"]),
            Shortcut(label: "Otwórz folder", keys: ["⌘O"]),
            Shortcut(label: "Ustawienia", keys: ["⌘,"]),
        ]),
        Group(title: "Decyzje", items: [
            Shortcut(label: "Usuń od razu do Kosza", keys: ["⌫"]),
            Shortcut(label: "Do usunięcia przy eksporcie (przełącz)", keys: ["X"]),
            Shortcut(label: "Ciemnia (przełącz)", keys: ["C"]),
        ]),
        Group(title: "Podgląd (przytrzymaj)", items: [
            Shortcut(label: "Zoom", keys: ["Z"]),
            Shortcut(label: "Przy zoomie: przybliż / oddal o stopień", keys: ["=", "-"]),
            Shortcut(label: "Przed/po", keys: ["M"]),
            Shortcut(label: "Podgląd RAW", keys: ["B"]),
        ]),
        Group(title: "Edycja", items: [
            Shortcut(label: "Światło i kolor", keys: ["E"]),
            Shortcut(label: "Kadr i prostowanie", keys: ["R"]),
            Shortcut(label: "Powrót z edycji do przeglądania (w narzędziu Kadr także Enter)", keys: ["D"]),
            Shortcut(label: "Resetuj edycję", keys: ["⇧⌘R"]),
            Shortcut(label: "Cofnij / ponów edycję", keys: ["⌘Z", "⇧⌘Z"]),
            Shortcut(label: "Wyjście z edycji / wyczyszczenie zaznaczenia", keys: ["Esc"]),
        ]),
        Group(title: "Balans bieli", items: [
            Shortcut(label: "Kopiuj", keys: ["⇧⌘C"]),
            Shortcut(label: "Wklej", keys: ["⇧⌘V"]),
        ]),
        Group(title: "Zaznaczanie", items: [
            Shortcut(label: "Zaznacz wszystkie (siatka)", keys: ["⌘A"]),
            Shortcut(label: "Poruszanie się po siatce", keys: ["←", "↑", "↓", "→"]),
            Shortcut(label: "Ściąga skrótów", keys: ["?"]),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { model.showShortcuts = false }
            dialog
        }
        .background { Color.clear.accessibilityIdentifier("overlay.shortcuts") }
    }

    private var dialog: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Skróty klawiszowe").font(.system(size: 17, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    KeyCap("?")
                    Text("lub")
                    KeyCap("esc")
                    Text("zamyka")
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 3), alignment: .leading, spacing: 4) {
                ForEach(Self.groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.secondaryText)
                            .padding(.top, 16).padding(.bottom, 4)
                        ForEach(group.items) { item in
                            HStack(spacing: 10) {
                                Text(item.label).font(.system(size: 12.5))
                                Spacer(minLength: 6)
                                HStack(spacing: 3) { ForEach(item.keys, id: \.self) { KeyCap($0) } }
                            }
                            .padding(.vertical, 5)
                            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5) }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("shortcut.\(item.id)")
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(.horizontal, 30).padding(.top, 26).padding(.bottom, 24)
        .frame(width: 880)
        .background(Color(red: 40 / 255, green: 40 / 255, blue: 42 / 255, opacity: 0.97), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.6), radius: 40, y: 30)
    }
}

private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white.opacity(0.9))
    }
}
