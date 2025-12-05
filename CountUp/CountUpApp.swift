//
//  CountUpApp.swift
//  CountUp
//
//  Created by problaze20 on 28/11/25.
//

import SwiftUI
import Cocoa
import HotKey

@main
struct CountUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - LAUNCH AT LOGIN API (macOS 13+)
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    enum State: String, Codable {
        case stopped, running, paused
    }

    var statusItem: NSStatusItem!
    var timer: Timer?
    var startTime: Date?
    var accumulated: TimeInterval = 0
    var state: State = .stopped
    var toggleHotKey: HotKey?  // Start/Pause/Resume
    var resetHotKey: HotKey?   // Reset
    
    // Store checkbox state
    var isLaunchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return false
            }
        }
        set {
            if #available(macOS 13.0, *) {
                if newValue {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
        }
    }
    
    // MARK: - STATE PERSISTENCE

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(state.rawValue, forKey: "stopwatchState")
        defaults.set(accumulated, forKey: "stopwatchAccumulated")
        defaults.set(startTime, forKey: "stopwatchStartTime")
    }

    func restoreState() {
        let defaults = UserDefaults.standard
        if let savedStateRaw = defaults.string(forKey: "stopwatchState"),
           let savedState = State(rawValue: savedStateRaw) {
            state = savedState
        }
        
        accumulated = defaults.double(forKey: "stopwatchAccumulated")
        startTime = defaults.object(forKey: "stopwatchStartTime") as? Date

        if state == .running {
            startTimer()
        }

        updateDisplay()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Option + Shift + Space → toggle timer
        toggleHotKey = HotKey(key: .space, modifiers: [.option, .shift])
        toggleHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            switch self.state {
            case .stopped: self.start()
            case .running: self.pause()
            case .paused:  self.resume()
            }
        }

        // Option + Shift + Backspace → reset timer
        resetHotKey = HotKey(key: .delete, modifiers: [.option, .shift])
        resetHotKey?.keyDownHandler = { [weak self] in
            self?.reset()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "0:00"
            btn.target = self
            btn.action = #selector(openMenu)
        }
        restoreState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
           saveState()
       }
    
    // MARK: - MENU

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        switch state {
        case .stopped:
            let startItem = NSMenuItem(title: "Start", action: #selector(start), keyEquivalent: " ")
            startItem.keyEquivalentModifierMask = [.option, .shift]
            menu.addItem(startItem)
        case .running:
            let pauseItem = NSMenuItem(title: "Pause", action: #selector(pause), keyEquivalent: " ")
            pauseItem.keyEquivalentModifierMask = [.option, .shift]
            menu.addItem(pauseItem)
            
            let resetItem = NSMenuItem(title: "Reset", action: #selector(reset), keyEquivalent: "\u{8}") // Backspace
            resetItem.keyEquivalentModifierMask = [.option, .shift]
            menu.addItem(resetItem)
        case .paused:
            let resumeItem = NSMenuItem(title: "Resume", action: #selector(resume), keyEquivalent: " ")
            resumeItem.keyEquivalentModifierMask = [.option, .shift]
            menu.addItem(resumeItem)
            
            let resetItem = NSMenuItem(title: "Reset", action: #selector(reset), keyEquivalent: "\u{8}") // Backspace
            resetItem.keyEquivalentModifierMask = [.option, .shift]
            menu.addItem(resetItem)
        }

        menu.addItem(.separator())
        
        // --- Launch at Login checkbox (macOS 13+ only) ---
        if #available(macOS 13.0, *) {
            let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            launchAtLoginItem.state = isLaunchAtLogin ? .on : .off
            launchAtLoginItem.target = self
            menu.addItem(launchAtLoginItem)
        }
        
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    @objc func openMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)

        // Reset menu (prevents stuck menu)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - ACTIONS

    @objc func start() { deferAction { [self] in
        startTimer()
        state = .running
        startTime = Date()
        accumulated = 0
        updateDisplay()
        saveState()
    }}

    @objc func pause() { deferAction { [self] in
        timer?.invalidate()
        timer = nil
        if let startTime = startTime {
            accumulated += Date().timeIntervalSince(startTime)
        }
        startTime = nil
        state = .paused
        updateDisplay()
        saveState()
    }}

    @objc func resume() { deferAction { [self] in
        state = .running
        startTime = Date()
        startTimer()
        updateDisplay()
        saveState()
    }}

    @objc func reset() { deferAction { [self] in
        timer?.invalidate()
        timer = nil
        accumulated = 0
        startTime = nil
        state = .stopped
        updateDisplay()
        saveState()
    }}
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let newState = sender.state != .on
            isLaunchAtLogin = newState
            sender.state = newState ? .on : .off
        }
    }

    func deferAction(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { block() }
    }

    // MARK: - TIMER

    func startTimer() {
        guard timer == nil else { return } // prevents duplicates

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func updateDisplay() {
        let elapsed: TimeInterval
        switch state {
        case .running:
            if let startTime = startTime {
                elapsed = accumulated + Date().timeIntervalSince(startTime)
            } else {
                elapsed = accumulated
            }
        case .paused, .stopped:
            elapsed = accumulated
        }

        statusItem.button?.title = format(elapsed)
    }

    // MARK: - FORMAT TIME

    func format(_ t: TimeInterval) -> String {
        let s = Int(t) % 60
        let m = (Int(t) / 60) % 60
        let h = Int(t) / 3600

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    // MARK: - QUIT

    @objc func quit() { deferAction { [self] in
        timer?.invalidate()
        timer = nil
        NSApplication.shared.terminate(nil)
    }}
}
