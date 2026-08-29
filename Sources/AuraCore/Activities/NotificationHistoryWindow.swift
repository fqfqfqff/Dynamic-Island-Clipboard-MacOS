import AppKit
import SwiftUI

/// Окно с журналом уведомлений.
///
/// Отдельное окно, а не раздел в вырезе: остров показывает то, что ждёт
/// ответа, а история — это чтение, и ей нужно место и прокрутка.
@MainActor
final class NotificationHistoryWindow {
    private var panel: NSPanel?

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: NotificationHistoryView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        // Содержимое сбрасываем вместе с окном: скрытое окно SwiftUI
        // продолжает жить и перерисовываться.
        panel?.contentView = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = t("ui.5f1a90e3", "История уведомлений")
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}

struct NotificationHistoryView: View {
    @State private var entries = NotificationArchive.recent()

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text(t("ui.b40e7215", "Пока пусто"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                            Divider().opacity(0.35)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            Divider()
            HStack {
                Text(String(format: t("ui.90b3ea77", "записей: %d"), entries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(t("ui.e2d0b419", "Очистить")) {
                    NotificationArchive.clear()
                    entries = []
                }
            }
            .padding(10)
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private func row(_ entry: NotificationArchive.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.sender)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let body = entry.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(entry.app)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
