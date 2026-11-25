import AppKit
import PhotoSiftCore
import SwiftUI

/// "Eksportuj do Album/": confirm, progress and done phases. Esc/Enter work in the confirm and done phases;
/// while exporting the sheet can only be stopped with "Zatrzymaj". Identifiers: `sheet.export`, `sheet.export.title`,
/// `sheet.export.summary`, `sheet.export.new`, `sheet.export.updated`, `sheet.export.skipped`, `sheet.export.conflicts`,
/// `sheet.export.note`, `sheet.export.cancel`, `sheet.export.confirm`, `sheet.export.progress.text`,
/// `sheet.export.progress.bar`, `sheet.export.progress.file`, `sheet.export.stop`, `sheet.export.done.text`,
/// `sheet.export.showInFinder`, `sheet.export.close`.
struct ExportSheet: View {
    let session: Session
    @State private var plan: ExportPlan?

    var body: some View {
        // The container must never be empty: SwiftUI does not fire `onAppear` for an empty view,
        // so an `if let plan` alone would leave the sheet blank forever.
        ZStack {
            if let plan {
                ExportSheetContent(session: session, plan: plan)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 460, height: 160)
            }
        }
        .onAppear {
            if plan == nil { plan = session.exportPlan() }
        }
    }
}

/// The phases of the export sheet for a plan computed once when the sheet appeared.
private struct ExportSheetContent: View {
    let session: Session
    let plan: ExportPlan
    @Environment(AppModel.self) private var model

    private enum Phase { case confirm, running, done }

    @State private var phase = Phase.confirm
    @State private var summary: ExportSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 40, height: 40)
                    .background(Palette.primary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityIdentifier("sheet.export.title")
                    switch phase {
                    case .confirm: confirmContent
                    case .running: runningContent
                    case .done: doneContent
                    }
                }
            }
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Palette.toolbar)
        .interactiveDismissDisabled(phase == .running)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.export")
    }

    private var title: String {
        switch phase {
        case .confirm: "Eksportuj do Album/"
        case .running: "Eksportowanie do Album/…"
        case .done: "Eksport zakończony"
        }
    }

    // MARK: Confirm

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(plan.newCount) \(PolishPlural.form(plan.newCount, one: "nowe", few: "nowe", many: "nowych")), \(plan.changedCount) do aktualizacji")
                .font(.system(size: 13))
                .accessibilityIdentifier("sheet.export.summary")
            HStack(spacing: 8) {
                counter(plan.newCount, "nowych", id: "sheet.export.new")
                counter(plan.changedCount, "do aktualizacji", id: "sheet.export.updated")
            }
            Text("Pominięte: \(skippedText).")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .accessibilityIdentifier("sheet.export.skipped")
            if plan.conflictCount > 0 {
                Text("\(plan.conflictCount) \(PolishPlural.form(plan.conflictCount, one: "zdjęcie", few: "zdjęcia", many: "zdjęć")) nie zostanie wyeksportowane: w Album/ jest już obcy plik o tej samej nazwie. Photo Sift go nie nadpisze.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sheet.export.conflicts")
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 13))
                Text("Eksport niczego z Album/ nie usuwa. Kopie zdjęć usuniętych lub wysłanych do Ciemni po wcześniejszym eksporcie usuń ręcznie w Finderze.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sheet.export.note")
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var skippedText: String {
        var text = "\(plan.darkroomSkippedCount) w Ciemni"
        if plan.rawOnlySkippedCount > 0 { text += ", \(plan.rawOnlySkippedCount) tylko RAW" }
        return text
    }

    private func counter(_ value: Int, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .accessibilityIdentifier(id)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Running

    private var runningContent: some View {
        let progress = session.exportProgress
        let total = progress?.total ?? plan.pendingCount
        let completed = min(progress?.completed ?? 0, total)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(completed) z \(total) \(PolishPlural.form(total, one: "zdjęcia", few: "zdjęć", many: "zdjęć"))")
                .font(.system(size: 13).monospacedDigit())
                .accessibilityIdentifier("sheet.export.progress.text")
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .tint(Palette.primary)
                .accessibilityIdentifier("sheet.export.progress.bar")
            Text(currentFileText(progress))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .accessibilityIdentifier("sheet.export.progress.file")
        }
    }

    private func currentFileText(_ progress: ExportProgress?) -> String {
        guard let progress, let entry = plan.entries.first(where: { $0.item.id == progress.currentID }) else { return "" }
        let name = entry.item.jpegURL?.lastPathComponent ?? progress.currentID
        let verb = entry.status == .changed ? "Aktualizuję" : progress.action == .rendering ? "Renderuję" : "Kopiuję"
        return "\(verb) \(name)"
    }

    // MARK: Done

    private var doneContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(doneText)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sheet.export.done.text")
            Capsule().fill((summary?.failed.isEmpty ?? true) ? Palette.green : Palette.amber).frame(height: 6)
        }
    }

    private var doneText: String {
        guard let summary else { return "" }
        let saved = summary.copied + summary.rendered
        var text = "Zapisano \(saved) \(PolishPlural.form(saved, one: "zdjęcie", few: "zdjęcia", many: "zdjęć")) w Album/. Nic nie zostało usunięte."
        if summary.wasCancelled { text += " Eksport został zatrzymany." }
        if !summary.failed.isEmpty { text += " Nie udało się zapisać: \(summary.failed.joined(separator: ", "))." }
        return text
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .confirm:
            Button("Anuluj") { model.sheet = nil }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("sheet.export.cancel")
            Button("Eksportuj") { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
                .accessibilityIdentifier("sheet.export.confirm")
        case .running:
            Button("Zatrzymaj") { session.cancelExport() }
                .accessibilityIdentifier("sheet.export.stop")
        case .done:
            Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([plan.albumURL]) }
                .accessibilityIdentifier("sheet.export.showInFinder")
            Button("Gotowe") { model.sheet = nil }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
                .accessibilityIdentifier("sheet.export.close")
            Button("") { model.sheet = nil }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func start() {
        phase = .running
        Task {
            summary = await session.runExport(plan: plan)
            phase = .done
        }
    }
}
