import IOKit.pwr_mgt

/// Пока витрина на экране, дисплею нельзя засыпать — иначе она погаснет
/// через минуту и весь смысл пропадёт.
final class PowerAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false

    func hold(reason: String) {
        guard !isHeld else { return }
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isHeld = status == kIOReturnSuccess
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
    }

    deinit {
        if isHeld { IOPMAssertionRelease(assertionID) }
    }
}
