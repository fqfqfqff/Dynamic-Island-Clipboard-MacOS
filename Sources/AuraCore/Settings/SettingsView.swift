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
    @State private var importedCount: Int?

    enum Section: String, CaseIterable, Identifiable {
        case island = "Остров"
        case player = "Плеер"
        case appearance = "Оформление"
        case showcase = "Витрина"
        case behaviour = "Поведение"
        case sources = "Источники"
        case notifications = "Уведомления"
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
            case .notifications: "bell.badge"
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
                VStack(alignment: .leading, spacing: 20) {
                    levelPicker
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(section.rawValue)
        }
        .frame(width: 720, height: 500)
    }

    /// Переключатель подробности. Стоит над всем, а не прячется в «Системе»:
    /// это первое решение, которое человек принимает, открыв окно.
    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $settings.detailLevel) {
                Text(t("ui.d4a10b96", "Минимум")).tag("minimal")
                Text(t("ui.7e3c05af", "Обычно")).tag("normal")
                Text(t("ui.b28f6d41", "Всё")).tag("all")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            hint(levelHint)
        }
        .padding(.bottom, 4)
    }

    private var levelHint: String {
        switch settings.detailLevel {
        case "minimal": "Только то, что меняют чаще всего."
        case "all": "Все настройки, включая тонкую подстройку размеров и кривых."
        default: "Обычный набор. «Всё» откроет тонкую подстройку."
        }
    }

    /// Настройки, которые нужны не каждому.
    @ViewBuilder
    private func advanced<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if settings.detailLevel == "all" { content() }
    }

    /// Настройки обычного уровня: скрыты только в «Минимуме».
    @ViewBuilder
    private func standard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if settings.detailLevel != "minimal" { content() }
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
        case .notifications: notifications
        case .clipboard: clipboard
        case .system: system
        }
    }

    // MARK: - Остров

    private var island: some View {
        VStack(alignment: .leading, spacing: 22) {
            advanced {
                group("Форма") {
                    slider("Скругление снизу", $settings.bottomCornerRadius, 0...40, "pt")
                    slider("Ширина боковых слотов", $settings.accessorySlotWidth, 28...80, "pt")
                    Toggle(t("ui.7749cde9", "Вывернутые верхние углы"), isOn: $settings.showWings)
                    hint("Вывернутые углы делают панель как бы вытекающей из выреза.")
                }
            }

            group("Раскрытая панель") {
                slider("Ширина", $settings.expandedWidth, 260...760, "pt")
                hint("Высота панели подбирается сама — по тому, что в ней сейчас лежит.")
                hint("Высота не опустится ниже содержимого плеера — оно всегда помещается целиком.")
            }

            group("Отклик на курсор") {
                Toggle(t("ui.e021a79c", "Реагировать на приближение"), isOn: $settings.reactToProximity)
                if settings.reactToProximity {
                    slider("Радиус реакции", $settings.proximityReach, 60...400, "pt")
                    hint("Чем ближе и быстрее курсор, тем резвее раскрывается остров.")
                }
            }

            group("Жесты") {
                Toggle(t("ui.cf016813", "Прокрутка вбок переключает трек"), isOn: $settings.scrollSwitchesTrack)
                Toggle(t("ui.74eee7cc", "Двойной клик ставит на паузу"), isOn: $settings.doubleClickTogglesPlayback)
                Toggle(t("ui.0d5c8a12", "Спрашивать, что делать с файлом"), isOn: $settings.dropShowsMenu)
                hint("Файл, бро́шенный на вырез: положить на полку, отправить по AirDrop или сжать в архив. Выключите — всё будет сразу ложиться на полку.")
                hint("Долгое нажатие на вырез открывает быстрое меню: пауза, спрятать остров, настройки.")
            }

            group("Движение") {
                slider("Характер", $settings.animationBounce, 0...1, "")
                hint(settings.animationBounce < 0.2
                     ? "Движение останавливается сразу, без отыгрыша."
                     : "Как на островке айфона: в конце движение чуть отыгрывает назад.")
            }

            advanced {
                group("Тонкая настройка движения") {
                    slider("Скорость анимаций", $settings.animationSpeed, 0.5...2, "×")
                    slider("Задержка раскрытия", $settings.hoverDelay, 0...1.2, "с")
                    slider("Сворачивать через", $settings.autoCollapseAfter, 0...30, "с")
                    hint(settings.autoCollapseAfter == 0
                         ? "Ноль — панель закрывается только когда курсор уходит."
                         : "Панель закроется сама через \(Int(settings.autoCollapseAfter)) с.")
                }
            }

            group("Подсказка при наведении") {
                Picker("", selection: $settings.hintStyle) {
                    Text(t("ui.c81a4b70", "Стрелка")).tag("chevron")
                    Text(t("ui.5f9d2e13", "Полоска")).tag("line")
                    Text(t("ui.a6e07c48", "Точка")).tag("dot")
                    Text(t("ui.a46dd922", "Ничего")).tag("none")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                standard {
                    slider("Насколько подрастает", $settings.peekGrowth, 8...40, "pt")
                }
            }

            advanced {
                group("Оформление панели") {
                    Toggle(t("ui.06462a53", "Тень под панелью"), isOn: $settings.showShadow)
                    Toggle(t("ui.67c2e385", "Тонкая обводка"), isOn: $settings.showBorder)
                    slider("Размытие подложки", $settings.backdropBlur, 0...120, "pt")
                    slider("Яркость подложки", $settings.backdropStrength, 0...1, "")
                }
            }

            standard {
                group("Правый значок у выреза") {
                    Picker("", selection: $settings.trailingSlotStyle) {
                        Text(t("ui.7f053917", "Полоски звука")).tag("bars")
                        Text(t("ui.bb14d99c", "Кольцо прогресса")).tag("progress")
                        Text(t("ui.93970437", "Текст")).tag("text")
                        Text(t("ui.a46dd922", "Ничего")).tag("none")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Плеер

    private var player: some View {
        VStack(alignment: .leading, spacing: 22) {
            advanced {
                group("Обложка") {
                    slider("Размер", $settings.artworkSize, 72...170, "pt")
                    slider("Скругление", $settings.artworkCornerRadius, 0...40, "pt")
                }
            }

            advanced {
                group("Текст") {
                    slider("Размер названия", $settings.titleFontSize, 12...22, "pt")
                }
            }

            group("Элементы") {
                Toggle(t("ui.2bd0d76a", "Полоса длительности"), isOn: $settings.showSeekBar)
                Toggle(t("ui.85474f45", "Показывать оставшееся время"), isOn: $settings.showRemainingTime)
                Toggle(t("ui.55296ac4", "Кнопки управления"), isOn: $settings.showControls)
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
                    Text(t("ui.a0d610b7", "Обложка")).tag("artwork")
                    Text(t("ui.4f7a89ea", "Градиент")).tag("gradient")
                    Text(t("ui.24587a10", "Чёрный")).tag("solid")
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

            advanced {
                group("Стекло") {
                    Picker("", selection: $settings.glassStyle) {
                        Text(t("ui.64962a2f", "Обычное")).tag("regular")
                        Text(t("ui.5a632c81", "Прозрачное")).tag("clear")
                        Text(t("ui.52335e29", "С подкраской")).tag("tinted")
                        Text(t("ui.d934aed1", "Выключено")).tag("off")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    hint("На macOS 26 используется системное стекло, на версиях ниже — материал.")
                }
            }

            group("Акцент") {
                Picker("", selection: $settings.accentSource) {
                    Text(t("ui.20834a93", "С обложки")).tag("artwork")
                    Text(t("ui.e51629de", "Свой цвет")).tag("fixed")
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

            advanced {
                group("Шрифт") {
                    Picker("", selection: $settings.fontDesign) {
                        Text(t("ui.eca17171", "Системный")).tag("default")
                        Text(t("ui.cdcedc31", "Скруглённый")).tag("rounded")
                        Text(t("ui.8be1fdf7", "С засечками")).tag("serif")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Витрина

    private var showcase: some View {
        VStack(alignment: .leading, spacing: 22) {
            standard {
                group("Расположение") {
                    Picker("", selection: $settings.showcaseLayout) {
                        Text(t("ui.77fb4be7", "Обложка и текст рядом")).tag("columns")
                        Text(t("ui.3f02d687", "Всё по центру")).tag("centered")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Toggle(t("ui.861db551", "Часы в углу"), isOn: $settings.showcaseClock)
                }
            }

            standard {
                group("Текст песни") {
                    Toggle(t("ui.a27f07b8", "Показывать текст"), isOn: $settings.showLyrics)
                    hint("Тексты берутся с открытой базы lrclib.net — туда уходят название трека, исполнитель и длительность. Работает для Музыки и Spotify.")
                }
            }

            group("Когда показывать") {
                Toggle(t("ui.08def347", "Показывать, когда я отошёл"), isOn: $settings.showcaseOnIdle)
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
                Toggle(t("ui.c44d80e0", "Раскрывать при наведении"), isOn: $settings.expandOnHover)
                hint(settings.expandOnHover
                     ? "Панель откроется, как только курсор дойдёт до выреза."
                     : "При наведении вырез только подрастает, панель открывается по клику.")
            }

            standard {
                group("Полноэкранный режим") {
                    Toggle(t("ui.49649472", "Прятать панель в полноэкранных приложениях"), isOn: $settings.hideInFullScreen)
                    hint("Иначе macOS показывает верхнюю кромку окна поверх видео.")
                }
            }

            standard {
                group("Несколько мониторов") {
                    Toggle(t("ui.43000da8", "Переносить панель на экран с курсором"), isOn: $settings.followMouseScreen)
                    hint("Выключено — панель живёт на экране с физическим вырезом.")
                }
            }

            advanced {
                group("Мониторы без выреза") {
                    slider("Ширина виртуального выреза", $settings.virtualNotchWidth, 120...320, "pt")
                    hint("Применяется после перезапуска Aura.")
                }
            }
        }
    }

    // MARK: - Уведомления

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Уведомления приложений") {
                Toggle(t("ui.bd27d183", "Уведомления приложений"), isOn: $settings.enableNotifications)
                hint("Требует Универсальный доступ. Системный баннер при этом остаётся — спрятать чужое окно приложение не может.")
            }

            group("Как показывать") {
                Picker("", selection: $settings.notificationStyle) {
                    Text(t("ui.71c0e9a4", "Карточкой из выреза")).tag("card")
                    Text(t("ui.4fd23b60", "Только значком")).tag("badge")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                hint(settings.notificationStyle == "card"
                     ? "Вырез вырастает сверху вниз: видно приложение, от кого и что пришло."
                     : "Вырез не растёт — слева появляется значок приложения, справа число непрочитанных.")
            }

            if settings.notificationStyle == "card" {
                group("Сколько держать карточку") {
                    slider("Время показа", $settings.notificationHold, 0...20, "с")
                    hint(settings.notificationHold == 0
                         ? "Карточка не исчезнет сама — останется, пока не откроете приложение."
                         : "Через \(Int(settings.notificationHold)) с карточка свернётся, а значок останется до прочтения. С кодом из СМС — на четыре секунды дольше: его читают и набирают руками.")
                }

                group(t("ui.702f981a", "Размер карточки")) {
                    slider(t("ui.bcf8b81c", "Крупнее обычного"), $settings.notificationScale, 1...1.6, "×")
                    hint(t("ui.e0c95a7c", "Уведомление читают мельком и боковым зрением — размер здесь важнее плотности. Вместе с текстом растут значок приложения и весь вырез."))
                }
            }

            group(t("ui.402d4a20", "Когда гасить значок")) {
                slider(t("ui.a444b797", "Сам погаснет через"), $settings.notificationBadgeTTL, 0...60, "мин")
                hint(settings.notificationBadgeTTL == 0
                     ? "Значок висит, пока не откроете приложение или не уберёте его кликом."
                     : "Уведомление, на которое не отреагировали за \(Int(settings.notificationBadgeTTL)) мин, — уже не новость: значок погаснет сам. Ноль отключает.")
            }

            group(t("ui.7e2b40c9", "Режим фокусирования")) {
                Toggle(t("ui.c93f8021", "Молчать, пока включён фокус"), isOn: $settings.respectFocus)
                hint("Режим фокусирования включают, чтобы не отвлекаться, и система при нём молчит. Карточка поверх — ровно то, от чего человек прятался. Значок при этом остаётся: он не отвлекает, а посмотреть, что пришло, можно самому.")
            }

            group(t("ui.a1c73f52", "Значки приложений")) {
                Toggle(t("ui.d4e91b07", "Снимать значок с баннера"), isOn: $settings.readIconsFromBanner)
                hint("Уведомления с айфона приходят от приложений, которых на Маке нет: Инстаграм, банк, доставка. Их иконку взять неоткуда — она есть только в самом баннере. Aura снимает с экрана квадрат 38×38 точек там, где система её нарисовала, и запоминает: второй раз снимать уже не нужно.")
                if PermissionStatus.screenRecording != .granted {
                    Button(t("ui.b8206c31", "Разрешить запись экрана")) {
                        PermissionStatus.open(.screenRecording)
                    }
                }
            }

            group("Что показывать") {
                Toggle(t("ui.83e5c17b", "Текст сообщения"), isOn: $settings.notificationShowBody)
                hint("Выключите, если не хотите, чтобы переписку было видно через плечо: тогда вырез покажет только отправителя и тип — голосовое, кружок, фото.")
                Toggle(t("ui.2ea94f30", "Обводка в цвет приложения"), isOn: $settings.notificationTintFromIcon)
            }

            standard {
                group("Прочитано") {
                    hint("Значок с числом непрочитанных исчезает, когда вы открываете само приложение, — узнать это иначе macOS не даёт.")
                }
            }
        }
    }

    // MARK: - Источники

    private var sources: some View {
        VStack(alignment: .leading, spacing: 22) {
            group(t("ui.5b1c9e40", "Звук")) {
                Toggle(t("ui.9f2a71d3", "Слушать звук"), isOn: $settings.listenToAudio)
                hint("Пока Aura слушает звук, macOS держит в строке меню свой значок записи — фиолетовую точку. Убрать её можно только перестав слушать. Без прослушивания полоски спектра рисуются по громкости, а из приложений остаются плееры и браузеры: отличить играющее приложение от того, которое просто держит открытый звук и молчит, больше нечем.")
            }

            group("Что показывать в вырезе") {
                Toggle(t("ui.7b8d5ba8", "Музыка и любой звук"), isOn: $settings.enableMusic)
                Toggle(t("ui.d7068ba5", "Снимки экрана"), isOn: $settings.enableScreenshots)
                if settings.enableScreenshots {
                    Toggle(t("ui.3c81ea47", "Класть снимок сразу в буфер обмена"),
                           isOn: $settings.copyScreenshotToClipboard)
                        .padding(.leading, 18)
                    hint("Снимок сохраняется на диск как обычно и одновременно попадает в буфер: ⌘V вставит картинку, а почта приложит файл. Скачанные и просто новые файлы буфер не трогают — только снимки.")
                }
                Toggle(t("ui.fe2a94d0", "Зарядка"), isOn: $settings.enableBattery)
                Toggle(t("ui.d6137b6d", "Режим фокусирования"), isOn: $settings.enableFocus)
                Toggle(t("ui.963d7c59", "Ближайшая встреча из Календаря"), isOn: $settings.enableCalendar)
                Toggle(t("ui.d05f2a91", "Wi-Fi и режим модема"), isOn: $settings.enableNetwork)
                Toggle(t("ui.6b40f9d2", "Загрузки браузера"), isOn: $settings.enableDownloads)
            }

            group(t("ui.4d7b0a91", "Макет плеера")) {
                Picker("", selection: $settings.playerLayout) {
                    Text(t("ui.9c1e4b30", "Крупный")).tag("large")
                    Text(t("ui.6f30d2a8", "Компактный")).tag("compact")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                hint("Крупный отдаёт под обложку двести с лишним точек, и раскрытый остров закрывает треть экрана. Компактный ставит обложку слева, а название и полосу справа — втрое ниже при той же читаемости.")
            }

            group("Spotify") {
                Toggle(t("ui.4b7e0d92", "Показывать всех исполнителей"), isOn: $settings.enrichSpotifyArtists)
                hint("В AppleScript у Spotify одно поле «исполнитель», и для трека с несколькими оно называет только первого. Остальных Aura берёт с публичной страницы трека — ключей для этого не нужно, но это сетевой запрос, один на трек.")
            }

            group("Наушники") {
                Toggle(t("ui.4e02b7c1", "Ставить на паузу, когда отключили наушники"),
                       isOn: $settings.pauseOnHeadphonesRemoved)
                hint("macOS делает это сама, но только для приложений, которые позаботились. Браузер обычно продолжает играть в динамики.")
            }

            group("Звук") {
                Toggle(t("ui.205bf115", "Полоски двигаются под реальный звук"), isOn: $settings.reactToAudio)
                hint("Требует разрешения на запись звука. Ничего не записывается — считаются только уровни частот.")
            }

            advanced {
                group("Свои активности") {
                    Text("Scripts/aura push --id build --title \"Сборка\" --progress 0.4")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Буфер

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("История") {
                Stepper("Хранить элементов: \(settings.clipboardLimit)",
                        value: $settings.clipboardLimit, in: 10...500, step: 10)
                Toggle(t("ui.13aa82ac", "Сохранять между запусками"), isOn: $settings.persistClipboard)
                hint("Картинки живут только до выхода из приложения и на диск не пишутся.")
            }

            standard {
                group("Не запоминать") {
                if settings.clipboardKnownSources.isEmpty {
                    hint("Здесь появятся приложения, из которых вы копировали. Любое можно исключить — из него в историю не попадёт ничего.")
                } else {
                    ForEach(settings.clipboardKnownSources, id: \.self) { app in
                        Toggle(app, isOn: Binding(
                            get: { !settings.clipboardExcludedApps.contains(app) },
                            set: { keep in
                                if keep {
                                    settings.clipboardExcludedApps.removeAll { $0 == app }
                                } else if !settings.clipboardExcludedApps.contains(app) {
                                    settings.clipboardExcludedApps.append(app)
                                }
                            }
                        ))
                    }
                    hint("Метку «не сохранять» ставят не все менеджеры паролей и не всякий банк-клиент — этот список закрывает остальных.")
                }
            }

            group("Вставка") {
                    Toggle(t("ui.ef37cbf6", "Вставлять сразу по клику"), isOn: $settings.autoPaste)
                    hint("Требует разрешения в «Конфиденциальность и безопасность → Универсальный доступ».")
                }
            }

            advanced {
                group("Журнал") {
                    Toggle(t("ui.2b5d528e", "Вести полный журнал копирований"), isOn: $settings.archiveEverything)
                    Button(t("ui.cc93f407", "Показать журнал в Finder")) { ClipboardArchive.revealInFinder() }
                    hint("Записывает всё скопированное, кроме картинок, без ограничения. Содержимое из менеджеров паролей не попадает.")
                }
            }
        }
    }

    // MARK: - Система

    private var system: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Запуск") {
                Toggle(t("ui.76872153", "Запускать при входе в систему"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                hint("Работает для копии в ~/Applications: приложение из папки сборки система зарегистрировать не даст.")
            }

            group("Язык интерфейса") {
                Picker("", selection: $settings.language) {
                    Text(t("ui.0b3f7d25", "Системный")).tag("system")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                hint("Применяется сразу, перезапуск не нужен.")
            }

            group("Профиль настроек") {
                HStack(spacing: 8) {
                    Button(t("ui.3e91c0b7", "Сохранить в файл")) { SettingsProfile.export() }
                    Button(t("ui.a05e2d13", "Загрузить из файла")) {
                        let applied = SettingsProfile.importProfile()
                        if applied > 0 { importedCount = applied }
                    }
                    ShareProfileButton()
                }
                if let importedCount {
                    hint("Применено параметров: \(importedCount). Настройки читаются при запуске — нажмите, чтобы перезапустить Aura.")
                    Button(t("ui.b6f2704c", "Перезапустить Aura")) { SettingsProfile.relaunch() }
                } else {
                    hint("Весь набор одним файлом: перенести на другую машину после переустановки или показать кому-то.")
                }
            }

            group("Разрешения") {
                Button(t("ui.e67eddc1", "Открыть экран настройки разрешений")) { AppActions.showOnboarding() }
                Button(t("ui.46ad51e9", "Запросить разрешения заново")) { settings.forgetPermissionPrompts() }
                hint("Aura спрашивает разрешения один раз. Если вы отказали случайно — эта кнопка позволит спросить снова.")
            }

            group("Готовые наборы") {
                ForEach(SettingsStore.Preset.allCases) { preset in
                    HStack(alignment: .top, spacing: 10) {
                        Button(preset.rawValue) { settings.apply(preset) }
                            .frame(width: 110, alignment: .leading)
                        Text(preset.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            group("Сброс") {
                Button(t("ui.ac282097", "Сбросить все настройки")) { settings.resetToDefaults() }
                Button(t("ui.2a2a0c98", "Выйти из Aura")) { AppActions.quit() }
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


/// Кнопка «Поделиться»: системному меню отправки нужен настоящий вид,
/// относительно которого оно раскроется.
private struct ShareProfileButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: t("ui.d1a0f36e", "Поделиться"), target: context.coordinator,
                              action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ view: NSButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @MainActor @objc func share(_ sender: NSButton) {
            SettingsProfile.share(from: sender)
        }
    }
}
