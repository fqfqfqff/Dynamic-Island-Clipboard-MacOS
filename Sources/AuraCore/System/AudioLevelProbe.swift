import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Правда ли из этого процесса идёт звук.
///
/// `kAudioProcessPropertyIsRunningOutput` отвечает «да» и тогда, когда
/// приложение просто держит открытый поток вывода и молчит в него. Так делают
/// Telegram, Discord и почти всё, что собрано на Electron: открыл окно —
/// и формально «играет». Из-за этого в вырезе висел плеер приложения,
/// которое ничего не воспроизводило.
///
/// Отличить можно только одним способом — послушать сам процесс. Тап
/// создаётся на конкретный процесс, из буферов берётся пиковая амплитуда;
/// всё, что нужно наружу, — «звучал ли он в последние секунды».
///
/// Требует того же разрешения на запись звука, что и полоски спектра,
/// и ключа `NSAudioCaptureUsageDescription` в Info.plist.
@MainActor
final class AudioLevelProbe {
    /// Процесс, который слушаем сейчас.
    private(set) var target = AudioObjectID(kAudioObjectUnknown)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// Удалось ли вообще создать тап: без разрешения на запись звука —
    /// нет, и тогда решение принимается без прослушивания.
    private(set) var isWorking = false

    /// До какого времени не пробуем снова.
    ///
    /// Раньше первая же неудача выключала прослушивание навсегда — до
    /// перезапуска приложения. Причин отказа хватает и временных: процесс
    /// исчез между опросом и созданием тапа, система занята. Из-за одной
    /// такой осечки обычные приложения переставали показываться совсем.
    private var retryAfter: Date?
    /// Код последней ошибки — чтобы `aura status` мог сказать, что именно
    /// не получилось, а не «не работает».
    private(set) var lastStatus: OSStatus = noErr

    /// Пауза между попытками. Создание тапа стоит десятки миллисекунд,
    /// пробовать на каждом опросе незачем.
    private nonisolated static let retryDelay: TimeInterval = 30

    /// Наблюдение, к которому имеет доступ аудио-поток.
    ///
    /// Отдельный объект, а не свойства зонда, и это не украшение. Замыкание,
    /// созданное внутри класса под главным актором, наследует его изоляцию —
    /// со всеми обращениями к `self`. CoreAudio зовёт это замыкание со своего
    /// потока, Swift на входе проверяет исполнителя, проверка не проходит,
    /// и процесс падает с SIGTRAP прямо в аудио-потоке. Поэтому колбэк
    /// не знает про зонд вовсе — только про эту коробку.
    private final class Observation: @unchecked Sendable {
        /// Время последнего громкого буфера и начала прослушивания.
        var lastLoud: TimeInterval = 0
        var startedAt: TimeInterval = 0
    }

    private let observation = Observation()

    /// Тише этого — тишина, а не тихая музыка. Примерно −54 дБ полной шкалы:
    /// разговор в голосовом сообщении на минимальной громкости всё ещё выше.
    ///
    /// Именно `static`, а не свойство: колбэк CoreAudio приходит со своего
    /// потока, и обращение оттуда к любому свойству объекта, изолированного
    /// главным актором, роняет процесс проверкой изоляции — даже если это
    /// неизменная константа.
    private nonisolated static let threshold: Float = 0.002

    /// Сколько молчания достаточно, чтобы признать источник немым. Между
    /// треками и фразами бывают паузы, поэтому не мгновенно.
    private nonisolated static let patience: TimeInterval = 2.5

    /// Сколько слушать, прежде чем вообще выносить вердикт.
    ///
    /// Отдельно от `patience`, и это выяснилось замером: агрегатное
    /// устройство с тапом раскручивается не мгновенно, первые буферы
    /// приходят через пару секунд. Пока их нет, тишина в тапе ничего
    /// не значит — а источник уже успевал попасть в немые и пропадал
    /// из выреза на весь срок карантина.
    private nonisolated static let warmup: TimeInterval = 4.5

    var isAvailable: Bool {
        guard let retryAfter else { return true }
        return retryAfter <= Date()
    }

    /// Человеческое описание состояния для диагностики.
    var summary: String {
        if isWorking { return "идёт" }
        if let retryAfter, retryAfter > Date() {
            return "ошибка \(lastStatus), повтор через \(Int(retryAfter.timeIntervalSinceNow)) с"
        }
        return "готово"
    }

    /// Вердикт: `nil` — слушаем недостаточно долго, чтобы утверждать.
    var isSilent: Bool? {
        guard isWorking else { return nil }
        let now = Date.timeIntervalSinceReferenceDate

        if now - observation.lastLoud < Self.patience { return false }
        // Пока не наслушались, молчание ничего не значит: приложение могло
        // попасть на паузу между фразами ровно в момент включения.
        guard now - observation.startedAt >= Self.warmup else { return nil }
        return true
    }

    /// Начать слушать процесс. Повторный вызов с тем же процессом ничего
    /// не делает: пересоздание тапа сбросило бы накопленное наблюдение.
    func listen(to object: AudioObjectID) {
        guard object != kAudioObjectUnknown else { return }
        guard object != target || !isWorking else { return }
        guard isAvailable else { return }

        stop()
        target = object
        observation.startedAt = Date.timeIntervalSinceReferenceDate
        observation.lastLoud = 0

        guard createTap(for: object), let uid = tapUID(), createAggregate(tapUID: uid), startIO()
        else {
            NSLog("Aura: не удалось послушать процесс, код %d", lastStatus)
            retryAfter = Date().addingTimeInterval(Self.retryDelay)
            stop()
            return
        }
        retryAfter = nil
        isWorking = true
    }

    func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }

        target = AudioObjectID(kAudioObjectUnknown)
        isWorking = false
    }

    // MARK: - Тап

    private func createTap(for object: AudioObjectID) -> Bool {
        let description = CATapDescription(stereoMixdownOfProcesses: [object])
        description.name = "Aura Level Probe"
        description.isPrivate = true
        // Звук должен продолжать играть в колонки, мы только слушаем.
        description.muteBehavior = .unmuted

        lastStatus = AudioHardwareCreateProcessTap(description, &tapID)
        return lastStatus == noErr && tapID != kAudioObjectUnknown
    }

    private func tapUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // CoreAudio отдаёт строку с +1: принимаем её как Unmanaged и
        // забираем владение, иначе она мостится мимо правил и утекает.
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue() else { return nil }
        return value as String
    }

    private func createAggregate(tapUID: String) -> Bool {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Aura Level Probe",
            kAudioAggregateDeviceUIDKey: "dev.kekch.aura.probe.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        lastStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        return lastStatus == noErr && aggregateID != kAudioObjectUnknown
    }

    private func startIO() -> Bool {
        let observation = self.observation

        // `@Sendable` и ни одного обращения к `self`: иначе замыкание уедет
        // в аудио-поток вместе с изоляцией главного актора и уронит процесс
        // на первой же проверке исполнителя.
        let block: AudioDeviceIOBlock = { @Sendable _, inputData, _, _, _ in
            // Единственная работа в аудио-потоке — найти пик. Ни разбора,
            // ни выделения памяти, ни переходов на главный поток.
            guard AudioLevelProbe.peak(of: inputData) > AudioLevelProbe.threshold else { return }
            observation.lastLoud = Date.timeIntervalSinceReferenceDate
        }

        lastStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, block)
        guard lastStatus == noErr, let procID else { return false }
        lastStatus = AudioDeviceStart(aggregateID, procID)
        return lastStatus == noErr
    }

    private nonisolated static func peak(of bufferList: UnsafePointer<AudioBufferList>) -> Float {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        var maximum: Float = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }

            var value: Float = 0
            vDSP_maxmgv(data.assumingMemoryBound(to: Float.self), 1, &value, vDSP_Length(count))
            maximum = max(maximum, value)
        }
        return maximum
    }
}
