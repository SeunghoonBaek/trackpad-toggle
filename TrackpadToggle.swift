import AppKit
import Darwin
import ServiceManagement

// These are the same private functions used by macOS Pointer Control settings.
// Resolve them at runtime so an OS change produces a useful error, not a crash.
final class TrackpadSetting {
    private typealias Getter = @convention(c) () -> Bool
    private typealias Setter = @convention(c) (Bool) -> Void
    private let handle: UnsafeMutableRawPointer
    private let getter: Getter
    private let setter: Setter

    init() throws {
        let path = "/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess"
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw failure("Could not load the macOS trackpad settings.")
        }
        guard let get = dlsym(library, "UAIgnoreTrackpadWhenExternalMouseEnabled"),
              let set = dlsym(library, "UAIgnoreTrackpadWhenExternalMouseSetEnabled") else {
            dlclose(library)
            throw failure("Trackpad settings are not available on this version of macOS.")
        }
        handle = library
        getter = unsafeBitCast(get, to: Getter.self)
        setter = unsafeBitCast(set, to: Setter.self)
    }

    deinit { dlclose(handle) }

    var ignoresBuiltInTrackpad: Bool { getter() }

    func setIgnoring(_ enabled: Bool) { setter(enabled) }
}

func failure(_ message: String) -> NSError {
    NSError(domain: "local.TrackpadToggle", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var setting: TrackpadSetting?
    private var loadError: Error?
    private var timer: Timer?
    private var changing = false
    private var lastState: Bool?
    private var helpWindow: NSWindow?
    private var helpStatus: NSTextField?
    private var helpToggle: NSButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        do { setting = try TrackpadSetting() }
        catch { loadError = error }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
        }
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 0.5
        if !UserDefaults.standard.bool(forKey: "hasShownHelp") {
            showHelp()
            UserDefaults.standard.set(true, forKey: "hasShownHelp")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHelp()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    @objc private func toggle() {
        guard !changing else { return }
        guard let setting else {
            showError(loadError ?? failure("Trackpad settings are not available."))
            return
        }
        changing = true
        let requested = !setting.ignoresBuiltInTrackpad
        setting.setIgnoring(requested)
        // Give the system preference notification time to reach other processes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.changing = false
            self.refresh(force: true)
            if setting.ignoresBuiltInTrackpad != requested {
                self.showError(failure("The setting did not change. Check its status in Pointer Control settings."))
            }
        }
    }

    private func refresh(force: Bool = false) {
        guard let button = item.button else { return }
        guard let setting else {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Setting unavailable")
            button.title = ""
            button.toolTip = "Trackpad Toggle: Setting unavailable. Right-click to open settings."
            button.setAccessibilityLabel("Trackpad Toggle: Setting unavailable")
            return
        }
        let ignored = setting.ignoresBuiltInTrackpad
        guard force || lastState != ignored else { return }
        lastState = ignored
        button.image = Self.trackpadIcon(ignored: ignored)
        button.title = ""
        let state = ignored ? "On" : "Off"
        button.toolTip = "Ignore Built-in Trackpad: \(state)\nApplies when an external mouse or trackpad is connected.\nClick to toggle. Right-click for the menu."
        button.setAccessibilityLabel("Trackpad Toggle: Ignore Built-in Trackpad \(state)")
        helpStatus?.stringValue = "Ignore Built-in Trackpad: \(state)"
        helpToggle?.title = ignored ? "Stop Ignoring Built-in Trackpad" : "Ignore Built-in Trackpad"
    }

    private static func trackpadIcon(ignored: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 18, height: 14),
                                       xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.4
            outline.stroke()
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: 3, y: 5))
            separator.line(to: NSPoint(x: 19, y: 5))
            separator.lineWidth = 1
            separator.stroke()
            if ignored {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 1, y: 17))
                slash.line(to: NSPoint(x: 21, y: 1))
                slash.lineWidth = 2
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func showMenu() {
        refresh()
        let menu = NSMenu()
        let ignored = setting?.ignoresBuiltInTrackpad
        let status = NSMenuItem(title: "Ignore Built-in Trackpad: \(ignored.map { $0 ? "On" : "Off" } ?? "Unavailable")",
                                action: nil, keyEquivalent: "")
        menu.addItem(status)
        menu.addItem(NSMenuItem(title: "Applies when an external mouse or trackpad is connected", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let toggleItem = NSMenuItem(title: ignored == true ? "Stop Ignoring Built-in Trackpad" : "Ignore Built-in Trackpad",
                                    action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = setting != nil && !changing
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        launchItem.target = self
        switch SMAppService.mainApp.status {
        case .enabled: launchItem.state = .on
        case .requiresApproval:
            launchItem.title = "Approve Launch at Login…"
            launchItem.state = .mixed
        default: launchItem.state = .off
        }
        menu.addItem(launchItem)
        let settingsItem = NSMenuItem(title: "Open Pointer Control Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let helpItem = NSMenuItem(title: "How to Use…", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Trackpad Toggle", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        // A permanent menu would consume left clicks, so show it only on demand.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch { showError(error) }
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Mouse") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showHelp() {
        if helpWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 270),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Trackpad Toggle"
            window.isReleasedWhenClosed = false
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            let heading = NSTextField(labelWithString: "Toggle from the Menu Bar")
            heading.font = .boldSystemFont(ofSize: 20)
            stack.addArrangedSubview(heading)
            let description = NSTextField(wrappingLabelWithString:
                "Click the trackpad icon to toggle Ignore Built-in Trackpad.\n\nSlashed icon: Ignore is on\nPlain icon: Ignore is off\nRight-click for launch options, settings, and Quit.")
            stack.addArrangedSubview(description)
            let status = NSTextField(labelWithString: "")
            helpStatus = status
            stack.addArrangedSubview(status)
            let buttons = NSStackView()
            buttons.spacing = 12
            let toggle = NSButton(title: "Toggle", target: self, action: #selector(toggle))
            toggle.bezelStyle = .rounded
            toggle.isEnabled = setting != nil
            helpToggle = toggle
            buttons.addArrangedSubview(toggle)
            let close = NSButton(title: "Close", target: self, action: #selector(closeHelp))
            close.bezelStyle = .rounded
            buttons.addArrangedSubview(close)
            stack.addArrangedSubview(buttons)
            let note = NSTextField(wrappingLabelWithString:
                "Applies when an external mouse or trackpad is connected.\nClosing this window keeps the app running in the menu bar.")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            stack.addArrangedSubview(note)
            window.contentView?.addSubview(stack)
            if let content = window.contentView {
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                    stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                    stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
                    stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
                ])
            }
            window.center()
            helpWindow = window
        }
        refresh(force: true)
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func closeHelp() { helpWindow?.close() }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Trackpad Toggle"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Pointer Control Settings")
        if alert.runModal() == .alertSecondButtonReturn { openSettings() }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
