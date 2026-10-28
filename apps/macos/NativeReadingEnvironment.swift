import AppKit
import IOKit.ps
import Network

/// Adapts laptop events to reading-session policy without owning a preview service.
final class NativeReadingEnvironment {
  private let onSleep: (Bool) -> Void
  private let onNetwork: () -> Void
  private let onPower: (Bool) -> Void
  private let network = NWPathMonitor()
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var powerSource: CFRunLoopSource?
  private var active = false

  init(
    onSleep: @escaping (Bool) -> Void,
    onNetwork: @escaping () -> Void,
    onPower: @escaping (Bool) -> Void
  ) {
    self.onSleep = onSleep
    self.onNetwork = onNetwork
    self.onPower = onPower
  }

  func start() {
    guard !active else { return }
    active = true
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) {
      [weak self] in self?.onSleep(true)
    }
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) {
      [weak self] in
      self?.updatePower()
      self?.onSleep(false)
    }
    observe(.default, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.updatePower() }
    observe(.default, ProcessInfo.thermalStateDidChangeNotification) {
      [weak self] in self?.updatePower()
    }
    powerSource = IOPSNotificationCreateRunLoopSource(
      { context in
        guard let context else { return }
        Unmanaged<NativeReadingEnvironment>.fromOpaque(context).takeUnretainedValue().updatePower()
      }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
    if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    network.pathUpdateHandler = { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.active else { return }
        self.onNetwork()
      }
    }
    network.start(queue: DispatchQueue(label: "lagrangian.network", qos: .utility))
    updatePower()
  }

  func dispose() {
    guard active else { return }
    active = false
    network.cancel()
    network.pathUpdateHandler = nil
    for (center, observer) in observers { center.removeObserver(observer) }
    observers.removeAll()
    if let powerSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
      CFRunLoopSourceInvalidate(powerSource)
    }
    powerSource = nil
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void
  ) {
    let observer = center.addObserver(forName: name, object: nil, queue: .main) {
      [weak self] _ in
      guard self?.active == true else { return }
      action()
    }
    observers.append((center, observer))
  }

  private func updatePower() {
    guard active else { return }
    let process = ProcessInfo.processInfo
    var battery = false
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
    {
      battery = (source as String) == kIOPSBatteryPowerValue
    }
    onPower(battery || process.isLowPowerModeEnabled || process.thermalState != .nominal)
  }

  deinit { dispose() }
}
