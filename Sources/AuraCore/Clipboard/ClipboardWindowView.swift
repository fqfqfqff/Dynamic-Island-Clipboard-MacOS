import SwiftUI

struct ClipboardWindowView: View {
    let onUse: (ClipboardItem) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var clipboard: ClipboardService
    @EnvironmentObject private var settings: SettingsStore
    @State private var query = ""
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool

    private var items: [ClipboardItem] {
        guard !query.isEmpty else { return clipboard.items }
        return clipboard.items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.sourceName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if needsAccessibility {
                permissionBanner
                Divider()
            }

            search
            Divider()

            if items.isEmpty {
                empty
            } else {
                list
            }

            footer
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            selection = items.first?.id
            searchFocused = true
        }
        .onExitCommand { onClose() }
        .background {
            // Стрелки и Enter обрабатываются кнопками-невидимками: поле поиска
            // держит фокус, а обычный onKeyPress до него бы не добрался.
            VStack {
                Button("") { move(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("") { move(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("") { useSelected() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    /// Без разрешения Accessibility элемент только копируется. Молчать об этом
    /// нельзя — со стороны выглядит как будто кнопка не работает.
    private var needsAccessibility: Bool {
        settings.autoPaste && !Paster.canPaste
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Aura пока только копирует, но не вставляет")
                    .font(.system(size: 11, weight: .medium))
                Text("Разрешите управление в «Конфиденциальность и безопасность → Универсальный доступ»")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Открыть") {
                settings.didAskAccessibility = true
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.12))
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск по истории", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { useSelected() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        ClipboardRow(item: item, isSelected: selection == item.id)
                            .id(item.id)
                            .contentShape(Rectangle())
                            // Выделение ведётся только клавишами: раньше оно
                            // прыгало за курсором, и список «перематывался» сам
                            // от любого движения мыши.
                            .onTapGesture { onUse(item) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selection) { _, new in
                guard let new else { return }
                withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "История пуста" : "Ничего не найдено")
                .font(.system(size: 13, weight: .medium))
            if query.isEmpty {
                Text("Скопируйте что-нибудь — оно появится здесь")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "вставить")
            hint("↑↓", "выбрать")
            hint("esc", "закрыть")
            Spacer()
            Text("\(clipboard.items.count) в истории")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button {
                AppActions.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Настройки Aura")

            Button {
                AppActions.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Выйти из Aura")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.25))
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func move(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        let next = min(max(0, current + offset), items.count - 1)
        selection = items[next].id
    }

    private func useSelected() {
        guard let selection, let item = items.first(where: { $0.id == selection }) else { return }
        onUse(item)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let source = item.sourceName {
                        Text(source)
                    }
                    Text(Self.formatter.string(from: item.date))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .color(let color):
            RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: color))
        default:
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
        }
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
