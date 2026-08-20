import SwiftUI

/// Настройки с боковым списком разделов.
///
/// Раньше здесь был `TabView`: разделов стало семь, они перестали помещаться
/// в ширину окна, и часть просто не показывалась. Список слева вмещает
/// сколько угодно и оставляет место под содержимое.
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var section: Section = .island
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    enum Section: String, CaseIterable, Identifiable {
        case island = "Остров"
        case player = "Плеер"
        case appearance = "Оформление"
        case showcase = "Витрина"
        case behaviour = "Поведение"
        case sources = "Источники"
        case clipboard = "Буфер"
        case system = "Система"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .island: "rectangle.topthird.inset.filled"
            case .player: "play.circle"
            case .appearance: "paintpalette"
            case .showcase: "rectangle.on.rectangle"
            case .behaviour: "hand.tap"
            case .sources: "waveform"
            case .clipboard: "doc.on.clipboard"
            case .system: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
        } detail: {
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(section.rawValue)
        }
        .frame(width: 720, height: 500)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .island: island
        case .player: player
        case .appearance: appearance
        case .showcase: showcase
        case .behaviour: behaviour
        case .sources: sources
        case .clipboard: clipboard
        case .system: system
        }
    }

    // MARK: - Остров

    private var island: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Форма") {
                slider("Скругление снизу", $settings.bottomCornerRadius, 0...40, "pt")
                slider("Ширина боковых слотов", $settings.accessorySlotWidth, 28...80, "pt")
                Toggle("Вывернутые верхние углы", isOn: $settings.showWings)
                hint("Вывернутые углы делают панель как бы вытекающей из выреза.")
            }

            group("Раскрытая панель") {
                slider("Ширина", $settings.expandedWidth, 260...760, "pt")
                slider("Высота", $settings.expandedHeight, 200...480, "pt")
                hint("Высота не опустится ниже содержимого плеера — оно всегда помещается целиком.")
            }

            group("Отклик на курсор") {
                Toggle("Реагировать на приближение", isOn: $settings.reactToProximity)
                if settings.reactToProximity {
                    slider("Радиус реакции", $settings.proximityReach, 60...400, "pt")
                    hint("Чем ближе и быстрее курсор, тем резвее раскрывается остров.")
                }
            }

            group("Жесты") {
                Toggle("Прокрутка над вырезом меняет громкость", isOn: $settings.scrollAdjustsVolume)
                Toggle("Прокрутка вбок переключает трек", isOn: $settings.scrollSwitchesTrack)
                Toggle("Двойной клик ставит на паузу", isOn: $settings.doubleClickTogglesPlayback)
            }

            group("Движение") {
                slider("Скорость анимаций", $settings.animationSpeed, 0.5...2, "×")
                slider("Задержка раскрытия", $settings.hoverDelay, 0...1.2, "с")
                slider("Сворачивать через", $settings.autoCollapseAfter, 0...30, "с")
                hint(settings.autoCollapseAfter == 0
                     ? "Ноль — панель закрывается только когда курсор уходит."
                     : "Панель закроется сама через \(Int(settings.autoCollapseAfter)) с.")
            }

            group("Оформление панели") {
                Toggle("Подсказка-стрелка при наведении", isOn: $settings.showChevronHint)
                Toggle("Тень под панелью", isOn: $settings.showShadow)
                Toggle("Тонкая обводка", isOn: $settings.showBorder)
                slider("Размытие подложки", $settings.backdropBlur, 0...120, "pt")
                slider("Яркость подложки", $settings.backdropStrength, 0...1, "")
            }

            group("Правый значок у выреза") {
                Picker("", selection: $settings.trailingSlotStyle) {
                    Text("Полоски звука").tag("bars")
                    Text("Кольцо прогресса").tag("progress")
                    Text("Текст").tag("text")
                    Text("Ничего").tag("none")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
    }

    // MARK: - Плеер

    private var player: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Обложка") {
                slider("Размер", $settings.artworkSize, 72...170, "pt")
                slider("Скругление", $settings.artworkCornerRadius, 0...40, "pt")
            }

            group("Текст") {
                slider("Размер названия", $settings.titleFontSize, 12...22, "pt")
            }

            group("Элементы") {
                Toggle("Полоса длительности", isOn: $settings.showSeekBar)
                Toggle("Показывать оставшееся время", isOn: $settings.showRemainingTime)
                Toggle("Кнопки управления", isOn: $settings.showControls)
                Stepper("Полосок эквалайзера: \(settings.barCount)",
                        value: $settings.barCount, in: 3...9)
            }
        }
    }

    // MARK: - Оформление

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Фон") {
                Picker("", selection: $settings.backgroundStyle) {
                    Text("Обложка").tag("artwork")
                    Text("Градиент").tag("gradient")
                    Text("Чёрный").tag("solid")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.backgroundStyle == "gradient" {
                    Picker("Градиент", selection: $settings.gradientPreset) {
                        ForEach(AuraTheme.gradients) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
            }

            group("Стекло") {
                Picker("", selection: $settings.glassStyle) {
                    Text("Обычное").tag("regular")
                    Text("Прозрачное").tag("clear")
                    Text("С подкраской").tag("tinted")
                    Text("Выключено").tag("off")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                hint("На macOS 26 используется системное стекло, на версиях ниже — материал.")
            }

            group("Акцент") {
                Picker("", selection: $settings.accentSource) {
                    Text("С обложки").tag("artwork")
                    Text("Свой цвет").tag("fixed")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.accentSource == "fixed" {
                    ColorPicker("Цвет", selection: Binding(
                        get: { AuraTheme.color(fromHex: settings.accentHex) ?? .pink },
                        set: { settings.accentHex = $0.hexString }
                    ))
                }
                hint("Акцентом красятся полоса прогресса, кнопка воспроизведения и полоски частот.")
            }

            group("Шрифт") {
                Picker("", selection: $settings.fontDesign) {
                    Text("Системный").tag("default")
                    Text("Скруглённый").tag("rounded")
                    Text("С засечками").tag("serif")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    // MARK: - Витрина

    private var showcase: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Расположение") {
                Picker("", selection: $settings.showcaseLayout) {
                    Text("Обложка и текст рядом").tag("columns")
                    Text("Всё по центру").tag("centered")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Toggle("Часы в углу", isOn: $settings.showcaseClock)
            }

            group("Текст песни") {
                Toggle("Показывать текст", isOn: $settings.showLyrics)
                hint("Тексты берутся с открытой базы lrclib.net — туда уходят название трека, исполнитель и длительность. Работает для Музыки и Spotify.")
            }

            group("Когда показывать") {
                Toggle("Показывать, когда я отошёл", isOn: $settings.showcaseOnIdle)
                if settings.showcaseOnIdle {
                    slider("Через", $settings.showcaseIdleMinutes, 1...15, "мин")
                }
                hint("Вручную — ⌥⌘M. На самом экране блокировки рисовать macOS не даёт; для этого есть заставка: Scripts/install-saver.sh")
            }
        }
    }

    // MARK: - Поведение

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Раскрытие") {
                Toggle("Раскрывать при наведении", isOn: $settings.expandOnHover)
                hint(settings.expandOnHover
                     ? "Панель откроется, как только курсор дойдёт до выреза."
                     : "При наведении вырез только подрастает, панель открывается по клику.")
            }

            group("Полноэкранный режим") {
                Toggle("Прятать панель в полноэкранных приложениях", isOn: $settings.hideInFullScreen)
                hint("Иначе macOS показывает верхнюю кромку окна поверх видео.")
            }

            group("Несколько мониторов") {
                Toggle("Переносить панель на экран с курсором", isOn: $settings.followMouseScreen)
                hint("Выключено — панель живёт на экране с физическим вырезом.")
            }

            group("Мониторы без выреза") {
                slider("Ширина виртуального выреза", $settings.virtualNotchWidth, 120...320, "pt")
                hint("Применяется после перезапуска Aura.")
            }
        }
    }

    // MARK: - Источники

    private var sources: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Что показывать в вырезе") {
                Toggle("Музыка и любой звук", isOn: $settings.enableMusic)
                Toggle("Громкость", isOn: $settings.enableVolume)
                Toggle("Снимки экрана", isOn: $settings.enableScreenshots)
                Toggle("Зарядка", isOn: $settings.enableBattery)
                Toggle("Наушники и Bluetooth", isOn: $settings.enableBluetooth)
                Toggle("Режим фокусирования", isOn: $settings.enableFocus)
                Toggle("Ближайшая встреча из Календаря", isOn: $settings.enableCalendar)
                Toggle("Уведомления приложений", isOn: $settings.enableNotifications)
                if settings.enableNotifications {
                    hint("Требует Универсальный доступ. Системный баннер при этом остаётся — спрятать чужое окно приложение не может.")
                }
            }

            group("Звук") {
                Toggle("Полоски двигаются под реальный звук", isOn: $settings.reactToAudio)
                hint("Требует разрешения на запись звука. Ничего не записывается — считаются только уровни частот.")
            }

            group("Свои активности") {
                Text("Scripts/aura push --id build --title \"Сборка\" --progress 0.4")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Буфер

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("История") {
                Stepper("Хранить элементов: \(settings.clipboardLimit)",
                        value: $settings.clipboardLimit, in: 10...500, step: 10)
                Toggle("Сохранять между запусками", isOn: $settings.persistClipboard)
                hint("Картинки живут только до выхода из приложения и на диск не пишутся.")
            }

            group("Вставка") {
                Toggle("Вставлять сразу по клику", isOn: $settings.autoPaste)
                hint("Требует разрешения в «Конфиденциальность и безопасность → Универсальный доступ».")
            }

            group("Журнал") {
                Toggle("Вести полный журнал копирований", isOn: $settings.archiveEverything)
                Button("Показать журнал в Finder") { ClipboardArchive.revealInFinder() }
                hint("Записывает всё скопированное, кроме картинок, без ограничения. Содержимое из менеджеров паролей не попадает.")
            }
        }
    }

    // MARK: - Система

    private var system: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Запуск") {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                hint("Работает для копии в ~/Applications: приложение из папки сборки система зарегистрировать не даст.")
            }

            group("Разрешения") {
                Button("Открыть экран настройки разрешений") { AppActions.showOnboarding() }
                Button("Запросить разрешения заново") { settings.forgetPermissionPrompts() }
                hint("Aura спрашивает разрешения один раз. Если вы отказали случайно — эта кнопка позволит спросить снова.")
            }

            group("Сброс") {
                Button("Сбросить все настройки") { settings.resetToDefaults() }
                Button("Выйти из Aura") { AppActions.quit() }
            }
        }
    }

    // MARK: - Строительные блоки

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        _ unit: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: value, in: range).frame(width: 200)
            Text(unit.isEmpty
                 ? String(format: "%.0f%%", value.wrappedValue * 100)
                 : (unit == "×" || unit == "с"
                    ? String(format: "%.1f %@", value.wrappedValue, unit)
                    : "\(Int(value.wrappedValue)) \(unit)"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}
