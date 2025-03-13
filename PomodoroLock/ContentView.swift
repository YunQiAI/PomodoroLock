import SwiftUI
import Combine
import AppKit

class PomodoroTimer: ObservableObject {
    @Published var workDuration: Int = 15 * 60
    @Published var breakDuration: Int = 5 * 60
    @Published var timeRemaining: Int = 15 * 60
    @Published var isRunning: Bool = false
    @Published var isBreakTime: Bool = false
    @Published var showMenuBarTimer: Bool = true

    private var timer: Timer?
    private var breakWindow: NSWindow?
    private var statusItem: NSStatusItem?

    init() {
        setupBreakWindow()
        setupMenuBar()
    }

    func start() {
        isRunning = true
        updateMenuBar()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
                self.updateMenuBar()
            } else {
                self.switchMode()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        resetTimer()
        updateMenuBar()
    }

    func resetTimer() {
        timeRemaining = isBreakTime ? breakDuration : workDuration
        updateMenuBar()
    }

    private func switchMode() {
        isRunning = false
        isBreakTime.toggle()
        resetTimer()
        if isBreakTime {
            startBreakTimer()
            showBreakWindow()
        }
    }

    func startBreakManually() {
        isBreakTime = true
        resetTimer()
        startBreakTimer()
        showBreakWindow()
    }

    private func startBreakTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
                self.updateMenuBar()
            } else {
                self.dismissBreakScreen()
            }
        }
    }

    private func setupBreakWindow() {
        DispatchQueue.main.async {
            let screenSize = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            self.breakWindow = NSWindow(contentRect: screenSize,
                                        styleMask: [.borderless],
                                        backing: .buffered,
                                        defer: false)
            self.breakWindow?.title = "休息模式"
            self.breakWindow?.level = .screenSaver
            self.breakWindow?.isOpaque = false
            self.breakWindow?.backgroundColor = NSColor.clear
            self.breakWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
            
            let blurView = NSVisualEffectView(frame: screenSize)
            blurView.blendingMode = .behindWindow
            blurView.material = .fullScreenUI
            blurView.state = .active
            
            let contentView = NSHostingView(rootView: BreakView(timer: self as PomodoroTimer))
            contentView.frame = screenSize
            blurView.addSubview(contentView)
            
            self.breakWindow?.contentView = blurView
        }
    }

    private func showBreakWindow() {
        DispatchQueue.main.async {
            self.breakWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func dismissBreakScreen() {
        DispatchQueue.main.async {
            self.breakWindow?.orderOut(nil)
            self.isBreakTime = false
            self.resetTimer()
            self.timer?.invalidate()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBar()
    }

    private func updateMenuBar() {
        guard let statusItem = statusItem, showMenuBarTimer else { return }
        statusItem.button?.title = isBreakTime ? "☕ \(timeString(timeRemaining))" : "🍅 \(timeString(timeRemaining))"
    }

    func timeString(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct BreakView: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack {
            Text("休息时间 ⏳")
                .font(.largeTitle)
                .foregroundColor(.white)
                .padding()

            Text(timer.timeString(timer.timeRemaining))
                .font(.system(size: 50, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding()

            Button("结束休息") {
                timer.dismissBreakScreen()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .foregroundColor(.white)
        }
    }
}

struct ContentView: View {
    @StateObject private var pomodoro = PomodoroTimer()

    var body: some View {
        VStack {
            Text(pomodoro.isBreakTime ? "休息时间" : "工作时间")
                .font(.largeTitle)
                .padding()

            Text(pomodoro.timeString(pomodoro.timeRemaining))
                .font(.system(size: 50, weight: .bold))
                .monospacedDigit()
                .padding()
            
            Toggle("菜单栏倒计时", isOn: $pomodoro.showMenuBarTimer)
                .padding()

            HStack {
                Button(pomodoro.isRunning ? "暂停" : "开始") {
                    pomodoro.isRunning ? pomodoro.pause() : pomodoro.start()
                }
                .buttonStyle(.borderedProminent)
                .padding()

                Button("停止") {
                    pomodoro.stop()
                }
                .buttonStyle(.bordered)
                .padding()
            }

            HStack {
                Text("工作时间: ")
                TextField("分钟", value: Binding(get: {
                    pomodoro.workDuration / 60
                }, set: { newValue in
                    pomodoro.workDuration = newValue * 60
                    pomodoro.resetTimer()
                }), formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 50)
            }
            .padding()

            HStack {
                Text("休息时间: ")
                TextField("分钟", value: Binding(get: {
                    pomodoro.breakDuration / 60
                }, set: { newValue in
                    pomodoro.breakDuration = newValue * 60
                    pomodoro.resetTimer()
                }), formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 50)
            }
            .padding()
            
            Button("立即进入休息模式") {
                pomodoro.startBreakManually()
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .frame(width: 300, height: 400)
    }
}

@main
struct PomodoroLockApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
