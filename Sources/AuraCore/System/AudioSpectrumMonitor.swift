import Accelerate
import AppKit
import AudioToolbox
import CoreAudio

/// Настоящий спектр того, что играет: полоски эквалайзера двигаются по
/// реальным частотам, а не по синусоидам.
///
/// Работает через процессный тап CoreAudio (публичный API с macOS 14.4):
/// создаётся тап на весь выход системы, поверх него — приватное агрегатное
/// устройство, с него читаются буферы. Дальше БПФ раскладывает сигнал по
/// пяти полосам.
///
/// Требует разрешения на запись звука: система спросит при первом запуске,
/// а в Info.plist обязан быть ключ `NSAudioCaptureUsageDescription` — без него
/// macOS откажет молча.
@MainActor
final class AudioSpectrumMonitor: ObservableObject {
    /// Уровни пяти полос, от низких частот к высоким. Значения 0…1.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 5)
    @Published private(set) var isRunning = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    private let bandCount = 5
    private let fftSize = 512
    private var fftSetup: FFTSetup?
    private var window: [Float]
    /// Сглаживание: без него полоски дёргаются на каждом кадре.
    private var smoothed: [CGFloat]
    /// Ограничитель частоты кадров, доступный аудио-потоку.
    ///
    /// Отдельный объект, а не свойство монитора, и это не украшение.
    /// Замыкание, созданное внутри класса под главным актором, наследует
    /// его изоляцию вместе со всеми обращениями к `self`. CoreAudio зовёт
    /// это замыкание со своего потока, Swift на входе проверяет исполнителя,
    /// проверка не проходит — и процесс падает с SIGTRAP.
    ///
    /// Так и было: Aura падала при каждом включении музыки, потому что тап
    /// спектра открывается ровно тогда, когда появляется звук.
    private final class FrameGate: @unchecked Sendable {
        var lastFrame: TimeInterval = 0
    }

    private let gate = FrameGate()
    /// Скользящий потолок громкости. Абсолютные значения после БПФ зависят от
    /// записи и системной громкости, поэтому шкалу приходится подстраивать:
    /// иначе полоски либо лежат на дне, либо всё время упираются в потолок.
    private var peaks: [Float]

    init() {
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        smoothed = Array(repeating: 0, count: bandCount)
        peaks = Array(repeating: 1e-6, count: bandCount)
    }

    /// Освобождать указатель БПФ в `deinit` нельзя: он не `Sendable`, а
    /// `deinit` не изолирован. Освобождаем при остановке — она всё равно
    /// вызывается перед уничтожением.

    // MARK: - Запуск

    func start() {
        guard !isRunning else { return }

        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))

        guard createTap(), let uid = tapUID(), createAggregate(tapUID: uid), startIO() else {
            NSLog("Aura: спектр звука недоступен — тап не создан")
            stop()
            return
        }
        isRunning = true
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
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
            self.fftSetup = nil
        }

        isRunning = false
        levels = Array(repeating: 0, count: bandCount)
    }

    private func createTap() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Aura Spectrum"
        description.isPrivate = true
        // Звук должен продолжать играть в колонки, мы только слушаем.
        description.muteBehavior = .unmuted

        return AudioHardwareCreateProcessTap(description, &tapID) == noErr
            && tapID != kAudioObjectUnknown
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
            kAudioAggregateDeviceNameKey: "Aura Spectrum",
            kAudioAggregateDeviceUIDKey: "dev.kekch.aura.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        return AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID) == noErr
            && aggregateID != kAudioObjectUnknown
    }

    private func startIO() -> Bool {
        let gate = self.gate

        // `@Sendable` и ни одного обращения к `self` до перехода на главный
        // поток: иначе замыкание уедет в аудио-поток вместе с изоляцией
        // главного актора и уронит процесс на первой же проверке исполнителя.
        let block: AudioDeviceIOBlock = { @Sendable [weak self] _, inputData, _, _, _ in
            // Буферы приходят около ста раз в секунду. Считать БПФ на каждом —
            // именно это и съедало процессор: отсекаем здесь, до всей работы.
            let now = Date.timeIntervalSinceReferenceDate
            guard now - gate.lastFrame >= 1.0 / 15 else { return }
            gate.lastFrame = now

            let samples = AudioSpectrumMonitor.mono(from: inputData)
            guard !samples.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.analyse(samples) }
            }
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, block)
        guard status == noErr, let procID else { return false }
        return AudioDeviceStart(aggregateID, procID) == noErr
    }

    // MARK: - Разбор

    /// Сводит все каналы в моно: для полосок стерео не нужно.
    /// `nonisolated` обязательно: зовётся из аудио-потока.
    private nonisolated static func mono(from bufferList: UnsafePointer<AudioBufferList>) -> [Float] {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard let first = buffers.first,
              let data = first.mData else { return [] }

        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
    }

    private func analyse(_ samples: [Float]) {
        guard let fftSetup, samples.count >= fftSize else { return }

        var input = Array(samples.prefix(fftSize))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(
                    realp: realPointer.baseAddress!,
                    imagp: imaginaryPointer.baseAddress!
                )
                input.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Полосы растут по ширине: слух различает низкие частоты подробнее,
        // поэтому равномерное деление спектра выглядело бы мёртвым.
        let edges = [1, 4, 12, 32, 80, half]
        var energies: [Float] = []
        for index in 0..<bandCount {
            let range = edges[index]..<min(edges[index + 1], half)
            guard !range.isEmpty else {
                energies.append(0)
                continue
            }
            energies.append(magnitudes[range].reduce(0, +) / Float(range.count))
        }

        // Потолок свой у каждой полосы: в музыке почти вся энергия лежит
        // в низах, и при общей шкале верхние полоски лежали бы на дне.
        // Он ползёт вниз медленно и мгновенно поднимается за громким звуком.
        var next: [CGFloat] = []
        for index in 0..<bandCount {
            peaks[index] = max(peaks[index] * 0.99, energies[index], 1e-7)
            // По уровню звука, а не по энергии: ухо слышит логарифмически.
            let ratio = sqrtf(energies[index] / peaks[index])
            next.append(CGFloat(max(0, min(1, ratio))))
        }

        for index in 0..<bandCount {
            // Быстрый подъём, медленный спад — так полоски отзываются на удар
            // и красиво опадают.
            let target = next[index]
            // Подъём заметно быстрее спада, но оба мягче прежнего: резкие
            // скачки читались как дёрганье.
            let factor: CGFloat = target > smoothed[index] ? 0.4 : 0.12
            smoothed[index] += (target - smoothed[index]) * factor
        }
        levels = smoothed
    }
}
