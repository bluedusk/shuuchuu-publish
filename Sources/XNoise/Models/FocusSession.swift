import Foundation
import Combine

enum SessionPhase: Equatable {
    case focus, shortBreak, longBreak
}

/// Pomodoro-style focus timer. Owns the countdown loop and the focus/break cycling.
/// Durations and cycle count come from `FocusSettings`.
@MainActor
final class FocusSession: ObservableObject {
    @Published private(set) var phase: SessionPhase = .focus
    @Published private(set) var remainingSec: Int
    @Published private(set) var currentSession: Int = 1
    @Published private(set) var isRunning: Bool = false

    let settings: FocusSettings
    private var timer: Timer?

    init(settings: FocusSettings) {
        self.settings = settings
        self.remainingSec = settings.focusMin * 60
    }

    var totalSessions: Int { settings.cycles }

    var totalSec: Int {
        switch phase {
        case .focus:       return settings.focusMin * 60
        case .shortBreak:  return settings.shortBreakMin * 60
        case .longBreak:   return settings.longBreakMin * 60
        }
    }

    var progress: Double {
        guard totalSec > 0 else { return 0 }
        return 1.0 - Double(remainingSec) / Double(totalSec)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleTimer()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        pause()
        phase = .focus
        currentSession = 1
        remainingSec = settings.focusMin * 60
    }

    func skip() {
        advancePhase()
    }

    // MARK: - Private

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard isRunning else { return }
        if remainingSec > 0 {
            remainingSec -= 1
        } else {
            advancePhase()
        }
    }

    private func advancePhase() {
        switch phase {
        case .focus:
            // After a focus period, go to short or long break.
            if currentSession >= settings.cycles {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        case .shortBreak:
            currentSession += 1
            phase = .focus
        case .longBreak:
            currentSession = 1
            phase = .focus
        }
        remainingSec = totalSec
    }
}

/// Durations / counts for the pomodoro. Mirrors the design's Settings page.
final class FocusSettings: ObservableObject {
    @Published var focusMin: Int       { didSet { defaults.set(focusMin, forKey: K.focus) } }
    @Published var shortBreakMin: Int  { didSet { defaults.set(shortBreakMin, forKey: K.shortBreak) } }
    @Published var longBreakMin: Int   { didSet { defaults.set(longBreakMin, forKey: K.longBreak) } }
    @Published var cycles: Int         { didSet { defaults.set(cycles, forKey: K.cycles) } }
    @Published var fadeIn: FadeIn      { didSet { defaults.set(fadeIn.rawValue, forKey: K.fadeIn) } }
    @Published var fadeOut: Bool       { didSet { defaults.set(fadeOut, forKey: K.fadeOut) } }
    @Published var pauseOnBreak: Bool  { didSet { defaults.set(pauseOnBreak, forKey: K.pauseOnBreak) } }
    @Published var chime: Bool         { didSet { defaults.set(chime, forKey: K.chime) } }
    @Published var breakReminder: Bool { didSet { defaults.set(breakReminder, forKey: K.breakReminder) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: K.launchAtLogin) } }
    @Published var menubarTimer: Bool  { didSet { defaults.set(menubarTimer, forKey: K.menubarTimer) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.focusMin      = (defaults.object(forKey: K.focus) as? Int) ?? 25
        self.shortBreakMin = (defaults.object(forKey: K.shortBreak) as? Int) ?? 5
        self.longBreakMin  = (defaults.object(forKey: K.longBreak) as? Int) ?? 15
        self.cycles        = (defaults.object(forKey: K.cycles) as? Int) ?? 4
        let rawFade = defaults.string(forKey: K.fadeIn) ?? FadeIn.two.rawValue
        self.fadeIn        = FadeIn(rawValue: rawFade) ?? .two
        self.fadeOut       = (defaults.object(forKey: K.fadeOut) as? Bool) ?? true
        self.pauseOnBreak  = (defaults.object(forKey: K.pauseOnBreak) as? Bool) ?? false
        self.chime         = (defaults.object(forKey: K.chime) as? Bool) ?? true
        self.breakReminder = (defaults.object(forKey: K.breakReminder) as? Bool) ?? true
        self.launchAtLogin = (defaults.object(forKey: K.launchAtLogin) as? Bool) ?? false
        self.menubarTimer  = (defaults.object(forKey: K.menubarTimer) as? Bool) ?? true
    }

    private enum K {
        static let focus         = "x-noise.focus.focusMin"
        static let shortBreak    = "x-noise.focus.shortBreakMin"
        static let longBreak     = "x-noise.focus.longBreakMin"
        static let cycles        = "x-noise.focus.cycles"
        static let fadeIn        = "x-noise.focus.fadeIn"
        static let fadeOut       = "x-noise.focus.fadeOut"
        static let pauseOnBreak  = "x-noise.focus.pauseOnBreak"
        static let chime         = "x-noise.focus.chime"
        static let breakReminder = "x-noise.focus.breakReminder"
        static let launchAtLogin = "x-noise.focus.launchAtLogin"
        static let menubarTimer  = "x-noise.focus.menubarTimer"
    }
}

enum FadeIn: String, CaseIterable, Codable, Identifiable {
    case off, two = "2s", eight = "8s"
    var id: String { rawValue }
    var display: String { rawValue }
    var seconds: Double {
        switch self { case .off: return 0; case .two: return 2; case .eight: return 8 }
    }
}
