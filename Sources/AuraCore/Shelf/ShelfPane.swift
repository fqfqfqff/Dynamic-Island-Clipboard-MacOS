import SwiftUI
import UniformTypeIdentifiers

/// Лента полки в раскрытой панели.
struct ShelfPane: View {
    @EnvironmentObject private var shelf: ShelfService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("ui.e7af584e", "Полка"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Button(t("ui.98b2073e", "Очистить")) { shelf.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shelf.items) { item in
                        card(item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func card(_ item: ShelfService.Item) -> some View {
        VStack(spacing: 4) {
            Group {
                if let preview = item.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.white.opacity(0.1))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.name)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .frame(width: 56)
        }
        // Перетаскивание обратно: файл уезжает в письмо или чат прямо отсюда.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button(t("ui.1259571a", "Открыть")) { NSWorkspace.shared.open(item.url) }
            Button(t("ui.9e3e457e", "Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button(t("ui.82c47049", "Убрать с полки")) { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
