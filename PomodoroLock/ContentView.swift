import SwiftUI
import Combine
import AppKit
import AVFoundation
import IOKit.pwr_mgt // 导入IOKit电源管理模块

// 创建一个全局单例PomodoroTimer
let sharedPomodoroTimer = PomodoroTimer()

class PomodoroTimer: ObservableObject {
    @Published var workDuration: Int = 15 * 60
    @Published var breakDuration: Int = 5 * 60
    @Published var timeRemaining: Int = 15 * 60
    @Published var isRunning: Bool = false
    @Published var isBreakTime: Bool = false
    @Published var showMenuBarTimer: Bool = true {
        didSet {
            if showMenuBarTimer != oldValue {
                updateMenuBarVisibility()
            }
        }
    }
    @Published var autoEndBreak: Bool = false // 是否自动结束休息

    private var timer: Timer?
    private var breakWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var audioPlayer: AVAudioPlayer?
    private var sleepAssertion: IOPMAssertionID = 0 // 用于存储休眠断言ID

    init() {
        setupBreakWindow()
        setupMenuBar()
    }

    func start() {
        // 确保先停止任何可能正在运行的计时器
        timer?.invalidate()
        
        isRunning = true
        updateMenuBar()
        
        // 使用RunLoop.main.add方法添加计时器，提高精度
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
                self.updateMenuBar()
            } else {
                self.switchMode()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        resetTimer()
        updateMenuBar()
    }

    func resetTimer() {
        timeRemaining = isBreakTime ? breakDuration : workDuration
        updateMenuBar()
    }

    private func switchMode() {
        // 确保先停止任何可能正在运行的计时器
        timer?.invalidate()
        timer = nil
        
        isRunning = false
        isBreakTime.toggle()
        resetTimer()
        
        if isBreakTime {
            startBreakTimer()
            showBreakWindow()
        } else {
            // 工作时间结束，播放提示音
            playSound()
        }
    }
    
    // 播放提示音 - 滴滴滴滴声
    private func playSound() {
        // 播放两次系统提示音，模拟"滴滴，滴滴"的效果
        NSSound.beep()
        
        // 延迟0.3秒后播放第二次提示音
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSSound.beep()
        }
        
        // 再延迟0.6秒后播放第三次提示音
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSSound.beep()
        }
        
        // 最后延迟0.9秒后播放第四次提示音
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            NSSound.beep()
        }
    }

    func startBreakManually() {
        isBreakTime = true
        resetTimer()
        startBreakTimer()
        showBreakWindow()
    }

    private func startBreakTimer() {
        // 确保先停止任何可能正在运行的计时器
        timer?.invalidate()
        
        // 阻止系统在休息期间休眠
        preventSleep()
        
        // 使用RunLoop.main.add方法添加计时器，提高精度
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
                self.updateMenuBar()
            } else {
                // 只有在autoEndBreak为true时才自动结束休息
                if self.autoEndBreak {
                    self.dismissBreakScreen()
                } else {
                    // 否则只播放提示音，但保持休息界面
                    self.playSound()
                    // 停止计时器，防止重复播放提示音
                    self.timer?.invalidate()
                    // 更新菜单栏显示00:00
                    self.updateMenuBar()
                }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func setupBreakWindow() {
        DispatchQueue.main.async {
            let screenSize = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            self.breakWindow = NSWindow(contentRect: screenSize,
                                        styleMask: [.borderless],
                                        backing: .buffered,
                                        defer: false)
            self.breakWindow?.title = NSLocalizedString("break_time", comment: "Break window title")
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
            // 确保先停止任何可能正在运行的计时器
            self.timer?.invalidate()
            self.timer = nil
            
            self.breakWindow?.orderOut(nil)
            self.isBreakTime = false
            self.resetTimer()
            
            // 恢复系统可以休眠
            self.allowSleep()
            
            // 注意：用户手动结束休息时不播放提示音
        }
    }
    
    // 结束休息并开始新的番茄工作周期
    func endBreakAndStartNewPomodoro() {
        DispatchQueue.main.async {
            // 确保先停止任何可能正在运行的计时器
            self.timer?.invalidate()
            self.timer = nil
            
            self.breakWindow?.orderOut(nil)
            self.isBreakTime = false
            self.resetTimer()
            
            // 恢复系统可以休眠
            self.allowSleep()
            
            // 注意：用户点击"继续番茄计时"时不播放提示音
            
            // 使用延迟确保前一个计时器完全停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.start() // 立即开始新的番茄工作周期
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarVisibility()
        updateMenuBar()
        setupMenuBarMenu()
    }
    
    // 根据showMenuBarTimer的值更新菜单栏图标的可见性
    private func updateMenuBarVisibility() {
        if showMenuBarTimer {
            // 如果菜单栏图标不存在，创建它
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                updateMenuBar()
                setupMenuBarMenu()
            }
        } else {
            // 如果菜单栏图标存在，移除它
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func updateMenuBar() {
        guard let statusItem = statusItem, showMenuBarTimer else { return }
        statusItem.button?.title = isBreakTime ? "☕ \(timeString(timeRemaining))" : "🍅 \(timeString(timeRemaining))"
        setupMenuBarMenu() // 更新菜单状态
    }
    
    private func setupMenuBarMenu() {
        let menu = NSMenu()
        
        // 打开主界面
        let openMainItem = NSMenuItem(title: NSLocalizedString("open_main_window", comment: "Menu item to open main window"),
                                     action: #selector(openMainWindow),
                                     keyEquivalent: "o")
        openMainItem.target = self
        menu.addItem(openMainItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 开始/暂停计时
        let startStopItem = NSMenuItem(title: isRunning ?
                                             NSLocalizedString("pause_timer", comment: "Menu item to pause timer") :
                                             NSLocalizedString("start_timer", comment: "Menu item to start timer"),
                                      action: #selector(toggleTimer),
                                      keyEquivalent: "p")
        startStopItem.target = self
        menu.addItem(startStopItem)
        
        // 停止计时
        let stopItem = NSMenuItem(title: NSLocalizedString("stop_timer", comment: "Menu item to stop timer"),
                                 action: #selector(stopTimerFromMenu),
                                 keyEquivalent: "s")
        stopItem.target = self
        menu.addItem(stopItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 退出应用
        let quitItem = NSMenuItem(title: NSLocalizedString("quit", comment: "Menu item to quit app"),
                                 action: #selector(quitApp),
                                 keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func openMainWindow() {
        // 使用全局AppDelegate引用来创建或显示主窗口
        if let appDelegate = sharedAppDelegate {
            appDelegate.createOrShowMainWindow()
        } else {
            // 如果无法获取AppDelegate，尝试使用旧方法
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func toggleTimer() {
        isRunning ? pause() : start()
        setupMenuBarMenu() // 更新菜单状态
    }
    
    @objc private func stopTimerFromMenu() {
        stop()
        setupMenuBarMenu() // 更新菜单状态
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func timeString(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 防止系统休眠
    private func preventSleep() {
        var assertionID: IOPMAssertionID = 0
        let reason = "PomodoroLock Break Time" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID)
        
        if success == kIOReturnSuccess {
            sleepAssertion = assertionID
            print("已阻止系统休眠")
        } else {
            print("无法阻止系统休眠")
        }
    }
    
    // 允许系统休眠
    private func allowSleep() {
        if sleepAssertion != 0 {
            let success = IOPMAssertionRelease(sleepAssertion)
            if success == kIOReturnSuccess {
                print("已恢复系统休眠")
                sleepAssertion = 0
            } else {
                print("无法恢复系统休眠")
            }
        }
    }
}

struct BreakView: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack {
            Text(timer.timeRemaining > 0 ? LocalizedStringKey("break_time_ongoing") : LocalizedStringKey("break_time_ended"))
                .font(.largeTitle)
                .foregroundColor(.white)
                .padding()

            Text(timer.timeString(timer.timeRemaining))
                .font(.system(size: 50, weight: .bold))
                .monospacedDigit()
                .foregroundColor(timer.timeRemaining > 0 ? .white : .green)
                .padding()

            Button(LocalizedStringKey("end_break")) {
                timer.dismissBreakScreen()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 5)
            .foregroundColor(.white)
            
            Button(LocalizedStringKey("continue_pomodoro")) {
                timer.endBreakAndStartNewPomodoro()
            }
            .buttonStyle(.bordered)
            .padding()
            .foregroundColor(.white)
            .background(Color.blue.opacity(0.6))
            .cornerRadius(8)
        }
    }
}

struct ContentView: View {
    @ObservedObject var pomodoro: PomodoroTimer = sharedPomodoroTimer

    var body: some View {
        VStack {
            Text(pomodoro.isBreakTime ? LocalizedStringKey("break_time") : LocalizedStringKey("work_time"))
                .font(.largeTitle)
                .padding()

            Text(pomodoro.timeString(pomodoro.timeRemaining))
                .font(.system(size: 50, weight: .bold))
                .monospacedDigit()
                .padding()
            
            VStack(alignment: .leading) {
                Toggle(LocalizedStringKey("menu_bar_display"), isOn: $pomodoro.showMenuBarTimer)
                    .help(LocalizedStringKey("menu_bar_display_help"))
                Toggle(LocalizedStringKey("auto_end_break"), isOn: $pomodoro.autoEndBreak)
                    .help(LocalizedStringKey("auto_end_break_help"))
            }
            .padding()

            HStack {
                Button(pomodoro.isRunning ? LocalizedStringKey("pause") : LocalizedStringKey("start")) {
                    pomodoro.isRunning ? pomodoro.pause() : pomodoro.start()
                }
                .buttonStyle(.borderedProminent)
                .padding()

                Button(LocalizedStringKey("stop")) {
                    pomodoro.stop()
                }
                .buttonStyle(.bordered)
                .padding()
            }

            HStack {
                Text(LocalizedStringKey("work_duration"))
                TextField(LocalizedStringKey("minutes"), value: Binding(get: {
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
                Text(LocalizedStringKey("break_duration"))
                TextField(LocalizedStringKey("minutes"), value: Binding(get: {
                    pomodoro.breakDuration / 60
                }, set: { newValue in
                    pomodoro.breakDuration = newValue * 60
                    pomodoro.resetTimer()
                }), formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 50)
            }
            .padding()
            
            Button(LocalizedStringKey("enter_break_mode")) {
                pomodoro.startBreakManually()
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .frame(width: 400, height: 500)
        .padding()
    }
}

// 全局AppDelegate引用，方便从其他地方访问
var sharedAppDelegate: AppDelegate?

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 保存全局引用
        sharedAppDelegate = self
        
        // 创建主窗口
        createOrShowMainWindow()
    }
    
    // 创建或显示主窗口
    func createOrShowMainWindow() {
        // 如果窗口已存在但被关闭，重新显示它
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 创建新窗口
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("PomodoroLock", comment: "Main window title")
        window.center()
        window.contentViewController = hostingController
        
        // 设置窗口关闭时的处理
        window.isReleasedWhenClosed = false
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        mainWindow = window
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 关闭窗口后应用继续在后台运行
    }
}

@main
struct PomodoroLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
