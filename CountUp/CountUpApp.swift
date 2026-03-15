//
//  CountUpApp.swift
//  CountUp
//
//  Created by problaze20 on 28/11/25.
//  Last Updated on 15/03/26
//
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

// MARK: - APP DELEGATE
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
    
    var toggleHotKey: HotKey?
    var resetHotKey: HotKey?
    
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
        
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to register launch at login: \(error.localizedDescription)")
        }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "0.00"
            btn.target = self
            btn.action = #selector(openMenu)
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        }
        
        restoreState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }
    
    // MARK: - HOTKEY SETUP
    
    private func setupHotKeys() {
        // Clear existing hotkeys
        toggleHotKey = nil
        resetHotKey = nil
    }
    
    
    // MARK: - MENU

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        
        switch state {
        case .stopped:
            let startItem = NSMenuItem(
                title: NSLocalizedString("start", comment: ""),
                action: #selector(start),
                keyEquivalent: ""
            )
            
            startItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Start Stopwatch")
            
            menu.addItem(startItem)
            
            let resetItem2 = NSMenuItem(title: NSLocalizedString("reset", comment: ""), action: nil, keyEquivalent: "")
            resetItem2.target = self
            resetItem2.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reset StopWatch")
            resetItem2.isEnabled = false

            menu.addItem(resetItem2)
            
        case .running:
            let pauseItem = NSMenuItem(title: NSLocalizedString("pause", comment: ""), action: #selector(pause), keyEquivalent: "")
            pauseItem.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause Stopwatch")
            menu.addItem(pauseItem)
            
            let resetItem = NSMenuItem(title: NSLocalizedString("reset", comment: ""), action: #selector(reset), keyEquivalent: "")
            resetItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reset StopWatch")
            menu.addItem(resetItem)
            
        case .paused:
            let resumeItem = NSMenuItem(title: NSLocalizedString("resume", comment: ""), action: #selector(resume), keyEquivalent: "")
            resumeItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume Stopwatch")
            menu.addItem(resumeItem)
            
            let resetItem = NSMenuItem(title: NSLocalizedString("reset", comment: ""), action: #selector(reset), keyEquivalent: "")
            resetItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reset StopWatch")
            menu.addItem(resetItem)
        }

        menu.addItem(.separator())
        
        menu.addItem(NSMenuItem(title: NSLocalizedString("quit-countup", comment: ""), action: #selector(quit), keyEquivalent: "q"))
        
        return menu
    }

    @objc func openMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)

        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - ACTIONS

    @objc func start() {
        deferAction { [self] in
            startTimer()
            state = .running
            startTime = Date()
            accumulated = 0
            updateDisplay()
            saveState()
        }
    }

    @objc func pause() {
        deferAction { [self] in
            timer?.invalidate()
            timer = nil
            if let startTime = startTime {
                accumulated += Date().timeIntervalSince(startTime)
            }
            startTime = nil
            state = .paused
            updateDisplay()
            saveState()
        }
    }

    @objc func resume() {
        deferAction { [self] in
            state = .running
            startTime = Date()
            startTimer()
            updateDisplay()
            saveState()
        }
    }

    @objc func reset() {
        deferAction { [self] in
            timer?.invalidate()
            timer = nil
            accumulated = 0
            startTime = nil
            state = .stopped
            updateDisplay()
            saveState()
        }
    }

    func deferAction(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { block() }
    }

    // MARK: - TIMER
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        
        timer?.tolerance = 0.003
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

        statusItem.button?.attributedTitle = formattedAttributedTime(elapsed)
    }

    // MARK: - FORMAT TIME

    func format(_ t: TimeInterval) -> String {
        let totalSeconds = Int(t)
        
        let cs = Int((t - Double(totalSeconds)) * 100) // centiseconds
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600
        
        if h > 0 {
            return String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
        } else if m > 0 {
            return String(format: "%d:%02d.%02d", m, s, cs)
        } else {
            return String(format: "%d.%02d", s, cs)
        }
    }
    
    func formattedAttributedTime(_ t: TimeInterval) -> NSAttributedString {
        let full = format(t)

        guard let dotRange = full.range(of: ".") else {
            return NSAttributedString(string: full)
        }

        let mainPart = String(full[..<dotRange.lowerBound])
        let csPart = String(full[dotRange.lowerBound...]) // includes ".xx"

        let mainAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .kern: 0.2
        ]

        let csAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let result = NSMutableAttributedString(string: mainPart, attributes: mainAttr)
        result.append(NSAttributedString(string: csPart, attributes: csAttr))

        return result
    }

    // MARK: - QUIT

    @objc func quit() {
        deferAction { [self] in
            timer?.invalidate()
            timer = nil
            NSApplication.shared.terminate(nil)
        }
    }
}
