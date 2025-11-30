//
//  CountUpApp.swift
//  CountUp
//
//  Created by problaze20 on 28/11/25.
//

import SwiftUI
import Cocoa

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

    enum State { case stopped, running, paused }

    var statusItem: NSStatusItem!
    var timer: Timer?
    var startTime: Date?
    var accumulated: TimeInterval = 0
    var state: State = .stopped
    
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "0:00"
            btn.target = self
            btn.action = #selector(openMenu)
        }
        startTimer()
    }

    // MARK: - MENU

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        switch state {
        case .stopped:
            menu.addItem(NSMenuItem(title: "Start",
                                    action: #selector(start), keyEquivalent: ""))
        case .running:
            menu.addItem(NSMenuItem(title: "Pause",
                                    action: #selector(pause), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Reset",
                                    action: #selector(reset), keyEquivalent: ""))
        case .paused:
            menu.addItem(NSMenuItem(title: "Resume",
                                    action: #selector(resume), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Reset",
                                    action: #selector(reset), keyEquivalent: ""))
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
        let menu = buildMenu()
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: .init(x: 0, y: button.bounds.height + 3), in: button)
        }
    }

    // MARK: - ACTIONS

    @objc func start() { deferAction { [self] in
        state = .running
        startTime = Date()
        accumulated = 0
        updateDisplay()
    }}

    @objc func pause() { deferAction { [self] in
        if let startTime = startTime {
            accumulated += Date().timeIntervalSince(startTime)
        }
        startTime = nil
        state = .paused
        updateDisplay()
    }}

    @objc func resume() { deferAction { [self] in
        state = .running
        startTime = Date()
        updateDisplay()
    }}

    @objc func reset() { deferAction { [self] in
        timer?.invalidate()
        timer = nil
        accumulated = 0
        startTime = nil
        state = .stopped
        updateDisplay()
        startTimer()
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
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
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
