// DualSense Battery — заряд подключённых геймпадов в строке меню.
//
// Источник — GameController.framework: macOS сам держит DualSense (и по Bluetooth,
// и по USB) и отдаёт батарею через GCController.battery. Сырой HID не нужен,
// и с chiaki/SDL, которые тоже открывают геймпад, это не конфликтует.
//
// Режимы:
//   dualsense-battery           — иконка в строке меню
//   dualsense-battery --once    — напечатать заряд в терминал и выйти

import AppKit
import GameController

// MARK: - Снимок состояния

struct Pad {
    let name: String
    let level: Int?            // 0…100, nil — геймпад ещё не прислал заряд
    let state: GCDeviceBattery.State
    let light: NSColor?        // цвет световой полосы — чтобы отличать два одинаковых

    var stateText: String {
        switch state {
        case .charging:    return "заряжается"
        case .full:        return "заряжен"
        case .discharging: return "от батареи"
        default:           return "—"
        }
    }

    var levelText: String { level.map { "\($0)%" } ?? "—" }
    var isLow: Bool { (level ?? 100) <= 20 && state == .discharging }
}

func snapshot() -> [Pad] {
    let controllers = GCController.controllers()
    // Два DualSense называются одинаково — нумеруем, если имя повторяется.
    var total: [String: Int] = [:]
    for c in controllers { total[baseName(c), default: 0] += 1 }
    var seen: [String: Int] = [:]

    return controllers.map { c in
        let base = baseName(c)
        seen[base, default: 0] += 1
        let name = total[base]! > 1 ? "\(base) \(seen[base]!)" : base

        var level: Int? = nil
        var state = GCDeviceBattery.State.unknown
        if let b = c.battery {
            state = b.batteryState
            // Пока геймпад не прислал первый отчёт, уровень 0 и состояние unknown.
            if !(b.batteryLevel == 0 && state == .unknown) {
                level = Int((b.batteryLevel * 100).rounded())
            }
        }
        let light = c.light.map {
            NSColor(srgbRed: CGFloat($0.color.red), green: CGFloat($0.color.green),
                    blue: CGFloat($0.color.blue), alpha: 1)
        }
        return Pad(name: name, level: level, state: state, light: light)
    }
}

func baseName(_ c: GCController) -> String {
    // productCategory — «DualSense», «DualShock 4», «Xbox One»…; vendorName длиннее.
    let cat = c.productCategory
    if !cat.isEmpty && cat != "Unknown" { return cat }
    return c.vendorName ?? "Геймпад"
}

// MARK: - CLI

func runOnce() {
    // Геймпады появляются в GCController.controllers() не мгновенно —
    // даём фреймворку время на перечисление.
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))

    let pads = snapshot()
    if pads.isEmpty {
        print("Геймпады не подключены")
        exit(1)
    }
    let width = pads.map(\.name.count).max()!
    for p in pads {
        let pad = p.name.padding(toLength: width, withPad: " ", startingAt: 0)
        let lvl = p.levelText.padding(toLength: 5, withPad: " ", startingAt: 0)
        print("\(pad)  \(lvl) \(p.stateText)")
    }
    exit(0)
}

// MARK: - Строка меню

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var timer: Timer?

    static let agentLabel = "com.geforester.dualsense-battery"
    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // Без этого фоновое приложение (LSUIElement) не получает события геймпада.
        GCController.shouldMonitorBackgroundEvents = true

        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageLeading

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: .GCControllerDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(refresh), name: .GCControllerDidDisconnect, object: nil)

        // Заряд DualSense меняется медленно и шагами по 10% — раз в 30 с за глаза.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        // Сразу после подключения батарея приходит с задержкой — догоняем.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func refresh() {
        let pads = snapshot()
        renderButton(pads)
        renderMenu(pads)
    }

    func renderButton(_ pads: [Pad]) {
        guard let button = item.button else { return }
        let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Геймпады")
        symbol?.isTemplate = true
        button.image = symbol

        if pads.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Геймпады не подключены"
            return
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let title = NSMutableAttributedString(string: " ")
        for (i, p) in pads.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            var text = p.levelText
            if p.state == .charging { text += "⚡︎" }
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if p.isLow { attrs[.foregroundColor] = NSColor.systemRed }
            title.append(NSAttributedString(string: text, attributes: attrs))
        }
        button.attributedTitle = title
        button.toolTip = pads.map { "\($0.name): \($0.levelText), \($0.stateText)" }.joined(separator: "\n")
    }

    func renderMenu(_ pads: [Pad]) {
        menu.removeAllItems()
        if pads.isEmpty {
            menu.addItem(disabled("Геймпады не подключены"))
        }
        for p in pads {
            let mi = disabled("\(p.name) — \(p.levelText), \(p.stateText)")
            if let c = p.light { mi.image = dot(c) }
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = FileManager.default.fileExists(atPath: App.agentURL.path) ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    // Автозапуск — обычный LaunchAgent, как у adaptive-brightness:
    // SMAppService с ad-hoc подписью ведёт себя непредсказуемо.
    @objc func toggleLogin() {
        let fm = FileManager.default
        let url = App.agentURL
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        } else {
            let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": App.agentLabel,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: url)
            }
        }
        refresh()
    }
}

// MARK: - Вход

if CommandLine.arguments.contains("--once") || CommandLine.arguments.contains("-1") {
    runOnce()
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
