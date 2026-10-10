import SwiftUI

@MainActor @Observable
final class HookSetupModel {
    private(set) var status: ClaudeHooks.Status = .notInstalled
    private(set) var plan: HookInstaller.Plan?
    private(set) var error: String?
    private(set) var result: String?

    func reload() {
        status = HookInstaller.status()
        do {
            plan = try HookInstaller.plan(install: status != .installed)
            error = nil
        } catch {
            plan = nil
            self.error = error.localizedDescription
        }
    }

    func apply() {
        guard let plan else { return }
        do {
            let backup = try HookInstaller.apply(plan)
            HookInstaller.removeLegacyFiles()
            reload()
            var text = plan.install ? "Zainstalowano. Hooki działają w nowych sesjach Claude Code."
                                    : "Odinstalowano — usunięte tylko wpisy NotchKeeper."
            if let backup { text += "\nKopia: \(backup.path)" }
            result = text
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct HookSetupView: View {
    @State private var model = HookSetupModel()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline).font(.headline)
            Text(HookInstaller.settingsURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)

            if let plan, plan.changes {
                DiffView(lines: plan.diff)
                Text("Przed zapisem zrobię kopię settings.json obok oryginału. Cudze hooki zostają bez zmian.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
            if let result = model.result {
                Text(result).foregroundStyle(.green).textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Zamknij") { dismissWindow(id: HookSetupView.windowID) }
                    .keyboardShortcut(.cancelAction)
                if let plan, plan.changes {
                    Button(actionTitle(plan)) { model.apply() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 200)
        .onAppear {
            model.reload()
        }
    }

    static let windowID = "hooks"

    private var plan: HookInstaller.Plan? { model.plan }

    private var headline: String {
        switch model.status {
        case .installed: "Hooki NotchKeeper są zainstalowane w Claude Code"
        case .outdated: "Hooki NotchKeeper wymagają aktualizacji"
        case .notInstalled: "Zainstaluj hooki NotchKeeper w Claude Code"
        }
    }

    private func actionTitle(_ plan: HookInstaller.Plan) -> String {
        guard plan.install else { return "Odinstaluj" }
        return model.status == .outdated ? "Zaktualizuj" : "Zainstaluj"
    }
}

/// Changed lines with 3 lines of context; longer unchanged runs fold into "⋯".
private struct DiffView: View {
    let lines: [LineDiff.Line]

    private struct Row: Identifiable {
        let id: Int
        let text: String
        let kind: Int // 0 same, 1 added, -1 removed, 2 fold
    }

    private var rows: [Row] {
        let changed = lines.indices.filter { if case .same = lines[$0] { false } else { true } }
        func near(_ i: Int) -> Bool { changed.contains { abs($0 - i) <= 3 } }
        var out: [Row] = []
        var folded = false
        for (i, line) in lines.enumerated() {
            switch line {
            case .added(let t): out.append(Row(id: i, text: "+ " + t, kind: 1)); folded = false
            case .removed(let t): out.append(Row(id: i, text: "- " + t, kind: -1)); folded = false
            case .same(let t) where near(i): out.append(Row(id: i, text: "  " + t, kind: 0)); folded = false
            case .same:
                if !folded { out.append(Row(id: i, text: "  ⋯", kind: 2)); folded = true }
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Text(row.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(row.kind == 2 ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .background(row.kind == 1 ? Color.green.opacity(0.18) : row.kind == -1 ? Color.red.opacity(0.18) : .clear)
                }
            }
            .textSelection(.enabled)
        }
        .frame(height: 320)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
