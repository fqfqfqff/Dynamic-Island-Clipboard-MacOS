import AppKit
import IOBluetooth
import SwiftUI

/// Наушники и прочие устройства Bluetooth: подключение, отключение и заряд.
///
/// Заряд AirPods система отдаёт только через `system_profiler`, а он думает
/// секунду-другую, поэтому запускается в фоне и только по событию подключения
/// либо раз в несколько минут.
/// Категория устройства. Определяется по классу из протокола Bluetooth,
/// а не по названию: «AirPods Максима» и «Наушники Гюзель» одинаково
/// являются аудиоустройствами, как их ни назови.
enum BluetoothCategory: String, Sendable {
    case headphones
    case speaker
    case phone
    case watch
    case keyboard
    case mouse
    case other

    var symbol: String {
        switch self {
        case .headphones: "airpods"
        case .speaker: "hifispeaker.fill"
        case .phone: "iphone"
        case .watch: "applewatch"
        case .keyboard: "keyboard"
        case .mouse: "magicmouse"
        case .other: "dot.radiowaves.left.and.right"
        }
    }

    var disconnectedSymbol: String {
        switch self {
        case .headphones: "airpods.gen3"
        case .phone: "iphone.slash"
        default: symbol
        }
    }

    var connectedTitle: String {
        switch self {
        case .headphones: "Наушники подключены"
        case .speaker: "Колонка подключена"
        case .phone: "Телефон рядом"
        case .watch: "Часы подключены"
        case .keyboard: "Клавиатура подключена"
        case .mouse: "Мышь подключена"
        case .other: "Устройство подключено"
        }
    }

    var disconnectedTitle: String {
        switch self {
        case .headphones: "Наушники отключены"
        case .speaker: "Колонка отключена"
        case .phone: "Телефон отключился"
        case .watch: "Часы отключены"
        case .keyboard: "Клавиатура отключена"
        case .mouse: "Мышь отключена"
        case .other: "Устройство отключено"
        }
    }

    /// Классы из спецификации Bluetooth: старший говорит о роде устройства,
    /// младший уточняет — наушники это или колонка.
    static func from(major: UInt32, minor: UInt32, name: String) -> BluetoothCategory {
        switch major {
        case 0x02: return .phone
        case 0x04:
            // 0x01 — гарнитура, 0x06 — наушники, 0x05 — громкоговоритель.
            return [0x01, 0x06].contains(minor) ? .headphones : .speaker
        case 0x05:
            if minor & 0x10 != 0 { return .keyboard }
            if minor & 0x20 != 0 { return .mouse }
            return .other
        case 0x07: return .watch
        default:
            return fromName(name)
        }
    }

    /// Запасной путь: некоторые устройства класс не сообщают.
    static func fromName(_ name: String) -> BluetoothCategory {
        let lower = name.lowercased()
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("наушник") {
            return .headphones
        }
        if lower.contains("iphone") || lower.contains("телефон") { return .phone }
        if lower.contains("watch") || lower.contains("часы") { return .watch }
        if lower.contains("keyboard") || lower.contains("клавиат") { return .keyboard }
        if lower.contains("mouse") || lower.contains("мышь") { return .mouse }
        if lower.contains("speaker") || lower.contains("колонка") { return .speaker }
        return .other
    }
}

/// Класс живёт на главном потоке, а колбэки IOBluetooth помечены
/// `nonisolated`: система зовёт их со своего потока, и попытка проверить
/// изоляцию прямо там заканчивалась падением. Данные с устройства снимаются
/// на месте вызова, а дальше уходят на главный поток уже значениями.
@MainActor
final class BluetoothActivityProvider: NSObject {
    private let center: ActivityCenter
    private var connectionObserver: IOBluetoothUserNotification?
    private var refreshTimer: Timer?
    private var knownConnected: Set<String> = []
    private var batteries: [String: DeviceBatteryValues] = [:]
    private var isReadingBattery = false

    init(center: ActivityCenter) {
        self.center = center
        super.init()
    }

    func start() {
        stop()

        // Первое обращение к Bluetooth поднимает системный запрос доступа,
        // а он блокирует поток до ответа пользователя. На главном потоке это
        // подвешивало всё приложение, поэтому спрашиваем в фоне и только
        // потом, уже с ответом, регистрируем наблюдателей.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let connected = paired.filter { $0.isConnected() }.compactMap(\.addressString)

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.knownConnected = Set(connected)
                    self.registerObservers()
                    self.readBatteries()
                }
            }
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readBatteries() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Уведомление о любом новом подключении. Отключение ловится отдельно,
    /// у каждого устройства своим наблюдателем.
    private func registerObservers() {
        connectionObserver = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectionObserver?.unregister()
        connectionObserver = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        knownConnected.removeAll()
    }

    // MARK: - События

    @objc nonisolated private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        // Само устройство через границу потока не отправляем: снимаем с него
        // всё нужное здесь и передаём дальше простые значения.
        let snapshot = DeviceSnapshot(device: device)
        device.register(
            forDisconnectNotification: self,
            selector: #selector(BluetoothActivityProvider.deviceDisconnected(_:device:))
        )

        Task { @MainActor [weak self] in
            guard let self, let address = snapshot.address else { return }
            self.knownConnected.insert(address)
            self.present(snapshot, connected: true)

            // Заряд появляется не сразу после соединения.
            try? await Task.sleep(for: .seconds(3))
            self.readBatteries()
        }
    }

    @objc nonisolated private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        let snapshot = DeviceSnapshot(device: device)

        Task { @MainActor [weak self] in
            guard let self, let address = snapshot.address else { return }
            self.knownConnected.remove(address)
            self.batteries[address] = nil
            self.present(snapshot, connected: false)
        }
    }

    private func present(_ device: DeviceSnapshot, connected: Bool) {
        let name = device.name
        let category = device.category
        let battery = device.address.flatMap { batteries[$0]?.displayValue }

        center.upsert(
            Activity(
                id: "bluetooth.\(device.address ?? name)",
                title: name,
                subtitle: connected ? category.connectedTitle : category.disconnectedTitle,
                symbol: connected ? category.symbol : category.disconnectedSymbol,
                tint: connected ? .blue : .gray,
                priority: .normal,
                indicator: battery.map { Activity.Indicator.text("\($0)%") } ?? .none,
                expiresAt: Date().addingTimeInterval(connected ? 6 : 4)
            )
        )
    }

    // MARK: - Заряд

    private func connectedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
    }

    private func readBatteries() {
        guard !isReadingBattery, !connectedDevices().isEmpty else { return }
        isReadingBattery = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.parseBatteries(from: Self.runProfiler())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isReadingBattery = false
                    for (name, battery) in parsed {
                        // Сопоставляем по имени: адрес profiler отдаёт рядом,
                        // но имя устройства читается человеком и стабильнее.
                        if let device = self.connectedDevices()
                            .first(where: { $0.name == name }),
                           let address = device.addressString {
                            self.batteries[address] = battery
                        }
                    }
                }
            }
        }
    }

    private static func runProfiler() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-detailLevel", "basic"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    /// Разбирает отступы вывода `system_profiler`: имя устройства — заголовок,
    /// уровни заряда — строки под ним.
    nonisolated static func parseBatteries(from output: String) -> [String: DeviceBatteryValues] {
        var result: [String: DeviceBatteryValues] = [:]
        var currentName: String?

        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasSuffix(":"), !line.contains("Battery"), !line.hasPrefix("Connected") {
                currentName = String(line.dropLast())
                continue
            }

            guard let name = currentName,
                  let percent = percentValue(from: line) else { continue }

            var values = result[name] ?? DeviceBatteryValues()
            if line.contains("Left") { values.left = percent }
            else if line.contains("Right") { values.right = percent }
            else if line.contains("Case") { values.caseLevel = percent }
            else if line.contains("Battery Level") { values.single = percent }
            result[name] = values
        }

        return result.filter { $0.value.displayValue != nil }
    }

    nonisolated private static func percentValue(from line: String) -> Int? {
        guard line.contains("Battery"), let range = line.range(of: ":") else { return nil }
        let tail = line[range.upperBound...]
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Int(tail)
    }

}

/// Снимок устройства: только те данные, которые нужны для показа.
/// Сам `IOBluetoothDevice` между потоками не передаётся — он для этого
/// не предназначен, и строгая проверка Swift 6 на это справедливо ругается.
struct DeviceSnapshot: Sendable {
    let name: String
    let address: String?
    let category: BluetoothCategory

    /// Собирается прямо в колбэке IOBluetooth, на его потоке: читаем
    /// свойства устройства там же, где их получили, и дальше несём
    /// только значения.
    nonisolated init(device: IOBluetoothDevice) {
        let name = device.name ?? "Устройство"
        self.name = name
        self.address = device.addressString
        self.category = BluetoothCategory.from(
            major: device.deviceClassMajor,
            minor: device.deviceClassMinor,
            name: name
        )
    }
}

/// Уровни заряда устройства. Вынесено наружу, чтобы разбор можно было
/// проверить тестами, не поднимая Bluetooth.
struct DeviceBatteryValues: Equatable {
    var left: Int?
    var right: Int?
    var single: Int?
    var caseLevel: Int?

    var displayValue: Int? {
        [left, right, single].compactMap { $0 }.min()
    }
}

