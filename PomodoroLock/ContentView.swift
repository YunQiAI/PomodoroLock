import SwiftUI
import Combine
import AppKit
import AVFoundation
import IOKit.pwr_mgt // 导入IOKit电源管理模块
import UserNotifications // 添加通知框架

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
    private var breakPanels: [NSPanel] = [] // 使用NSPanel替代NSWindow
    private var statusItem: NSStatusItem?
    private var audioPlayer: AVAudioPlayer?
    private var sleepAssertion: IOPMAssertionID = 0 // 用于存储休眠断言ID
    private var spaceChangeObserver: NSObjectProtocol? // 用于存储空间切换观察者
    private var missionControlObserver: NSObjectProtocol? // 用于存储Mission Control状态观察者
    private var isInMissionControl: Bool = false // 跟踪是否处于Mission Control状态

    init() {
        setupBreakWindow()
        setupMenuBar()
        setupKeyboardMonitoring()
        setupScreenChangeMonitoring() // 添加屏幕变化监听
        setupNotificationResponseHandling() // 添加通知响应处理
        setupSpaceChangeMonitoring() // 添加空间切换监听
        setupMissionControlMonitoring() // 添加Mission Control监听
    }
    
    deinit {
        // 移除通知监听
        if let observer = spaceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = missionControlObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
        // 确保释放休眠断言
        allowSleep()
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
            setupBreakWindow() // 重新设置窗口，确保捕获所有当前连接的显示器
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
        setupBreakWindow() // 重新设置窗口，确保捕获所有当前连接的显示器
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
            // 清除旧窗口
            for panel in self.breakPanels {
                panel.orderOut(nil)
            }
            self.breakPanels.removeAll()
            
            // 获取所有连接的显示器
            let screens = NSScreen.screens
            if !screens.isEmpty {
                // 为每个显示器创建一个窗口
                for screen in screens {
                    let screenFrame = screen.frame
                    
                    // 创建NSPanel而非NSWindow
                    let panel = NSPanel(
                        contentRect: screenFrame,
                        styleMask: [.borderless, .nonactivatingPanel], // 无边框且非激活面板
                        backing: .buffered,
                        defer: false,
                        screen: screen // 指定屏幕确保窗口显示在正确位置
                    )
                    panel.title = NSLocalizedString("break_time", comment: "Break window title")
                    panel.level = .screenSaver // 使用高窗口级别
                    panel.isOpaque = false
                    panel.backgroundColor = NSColor.clear
                    
                    // 设置重要的集合行为 - 增强穿透所有空间和全屏应用的能力
                    panel.collectionBehavior = [
                        .canJoinAllSpaces,    // 可以出现在所有空间
                        .fullScreenAuxiliary, // 允许出现在全屏应用上
                        .stationary,          // Mission Control时保持位置
                        .ignoresCycle         // 不参与应用切换循环
                    ]
                    
                    // 其他关键属性
                    panel.hidesOnDeactivate = false  // 应用非活跃时不隐藏
                    panel.hasShadow = false          // 不显示窗口阴影
                    panel.worksWhenModal = true      // 即使在模态状态下也工作
                    panel.ignoresMouseEvents = false // 捕获鼠标事件防止穿透
                    
                    // 设置窗口框架确保显示在正确的屏幕上
                    panel.setFrame(screenFrame, display: false)
                    
                    // 创建与之前相同的内容视图
                    let blurView = NSVisualEffectView(frame: NSRect(origin: .zero, size: screenFrame.size))
                    blurView.blendingMode = .behindWindow
                    blurView.material = .fullScreenUI
                    blurView.state = .active
                    
                    let contentView = NSHostingView(rootView: BreakView(timer: self))
                    contentView.frame = NSRect(origin: .zero, size: screenFrame.size)
                    blurView.addSubview(contentView)
                    
                    panel.contentView = blurView
                    
                    // 将面板添加到数组
                    self.breakPanels.append(panel)
                }
            } else {
                // 如果无法获取显示器信息，则创建一个默认窗口
                let fallbackFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
                let panel = NSPanel(
                    contentRect: fallbackFrame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.title = NSLocalizedString("break_time", comment: "Break window title")
                panel.level = .screenSaver
                panel.isOpaque = false
                panel.backgroundColor = NSColor.clear
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                panel.hidesOnDeactivate = false
                
                let blurView = NSVisualEffectView(frame: fallbackFrame)
                blurView.blendingMode = .behindWindow
                blurView.material = .fullScreenUI
                blurView.state = .active
                
                let contentView = NSHostingView(rootView: BreakView(timer: self))
                contentView.frame = fallbackFrame
                blurView.addSubview(contentView)
                
                panel.contentView = blurView
                
                self.breakPanels.append(panel)
            }
        }
    }

    private func showBreakWindow() {
        DispatchQueue.main.async {
            for panel in self.breakPanels {
                // 使用更强制的方法确保窗口显示
                panel.orderFrontRegardless()
                
                // 刷新窗口层级，确保保持在最前
                panel.level = .screenSaver
                
                // 对于某些特殊情况，尝试暂时改变并恢复窗口级别，强制刷新显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let originalLevel = panel.level
                    panel.level = .statusBar
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        panel.level = originalLevel
                        panel.orderFrontRegardless()
                    }
                }
            }
        }
    }

    func dismissBreakScreen() {
        DispatchQueue.main.async {
            // 确保先停止任何可能正在运行的计时器
            self.timer?.invalidate()
            self.timer = nil
            
            // 隐藏所有休息窗口
            for panel in self.breakPanels {
                panel.orderOut(nil)
            }
            
            self.isBreakTime = false
            self.resetTimer()
            
            // 恢复系统可以休眠
            self.allowSleep()
        }
    }
    
    // 结束休息并开始新的番茄钟周期
    func endBreakAndStartNewPomodoro() {
        // 先设置为工作模式
        isBreakTime = false
        
        // 重置计时器时间
        timeRemaining = workDuration
        
        // 隐藏所有休息窗口
        for panel in breakPanels {
            panel.orderOut(nil)
        }
        
        // 恢复系统可以休眠
        allowSleep()
        
        // 显式设置isRunning为true
        isRunning = true
        
        // 确保先停止任何可能正在运行的计时器
        timer?.invalidate()
        
        // 创建新的计时器
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
        
        // 更新菜单栏
        updateMenuBar()
    }

    // 添加空间切换监听 - 增强处理逻辑
    private func setupSpaceChangeMonitoring() {
        spaceChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isBreakTime else { return }
            
            // 更积极地多次尝试显示窗口，以便在各种场景下都能保证显示
            // 立即尝试一次
            self.showBreakWindow()
            
            // 延迟短暂时间再次尝试，配合系统动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showBreakWindow()
                
                // 如果刚从Mission Control退出，额外再尝试一次
                if self.isInMissionControl {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.showBreakWindow()
                        self.isInMissionControl = false
                    }
                }
            }
        }
    }
    
    // 添加Mission Control状态监听
    private func setupMissionControlMonitoring() {
        // 我们可以通过监测特定通知或系统状态来检测Mission Control的激活
        // 由于macOS没有直接的Mission Control通知，使用一个通用解决方案
        
        // 使用工作区通知作为替代方案
        missionControlObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, 
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isBreakTime else { return }
            
            // 标记可能处于Mission Control状态
            self.isInMissionControl = true
            
            // 在可能退出Mission Control时主动尝试显示窗口
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showBreakWindow()
            }
        }
        
        // 添加鼠标移动监视，在用户移动鼠标时可能是从Mission Control返回
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self, 
                  self.isBreakTime, 
                  self.isInMissionControl else { return }
            
            // 延迟执行，避免频繁调用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showBreakWindow()
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
    
    // 添加缺失的quitApp方法
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func setupKeyboardMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isBreakTime else { return event }
            
            if event.keyCode == 53 { // Esc键
                self.dismissBreakScreen()
                return nil // 消耗此事件
            } else if event.keyCode == 36 { // Enter键
                self.dismissBreakScreen()
                return nil // 消耗此事件
            }
            return event
        }
    }

    // 添加屏幕变化监听
    private func setupScreenChangeMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    // 处理屏幕变化事件
    @objc private func handleScreenChange() {
        // 只有在休息模式下才需要处理
        if isBreakTime {
            DispatchQueue.main.async {
                // 退出休息模式
                self.dismissBreakScreen()
                
                // 显示通知
                self.showScreenChangeNotification()
            }
        }
    }
    
    // 显示系统通知
    private func showScreenChangeNotification() {
        let center = UNUserNotificationCenter.current()
        
        // 创建开始新番茄周期的操作
        let startAction = UNNotificationAction(
            identifier: "START_POMODORO",
            title: NSLocalizedString("start_new_pomodoro", comment: "Start a new pomodoro"),
            options: .foreground
        )
        
        // 创建稍后再说的操作
        let laterAction = UNNotificationAction(
            identifier: "LATER",
            title: NSLocalizedString("later", comment: "Later"),
            options: .destructive
        )
        
        // 创建通知类别
        let category = UNNotificationCategory(
            identifier: "SCREEN_CHANGE",
            actions: [startAction, laterAction],
            intentIdentifiers: [],
            options: []
        )
        
        // 注册通知类别
        center.setNotificationCategories([category])
        
        // 请求通知权限
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("screen_change_title", comment: "Screen configuration changed")
                    content.body = NSLocalizedString("screen_change_message", comment: "Break mode was ended due to screen configuration change")
                    content.sound = UNNotificationSound.default
                    content.categoryIdentifier = "SCREEN_CHANGE" // 设置通知类别
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    center.add(request) { error in
                        if let error = error {
                            print("通知发送失败: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // 设置通知响应处理
    private func setupNotificationResponseHandling() {
        UNUserNotificationCenter.current().delegate = PomodoroNotificationDelegate.shared
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

// 修改类名避免重复声明
class PomodoroNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PomodoroNotificationDelegate()
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               didReceive response: UNNotificationResponse, 
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.actionIdentifier
        
        if identifier == "START_POMODORO" {
            // 用户选择了开始新的番茄周期
            DispatchQueue.main.async {
                sharedPomodoroTimer.stop()
                sharedPomodoroTimer.isBreakTime = false
                sharedPomodoroTimer.start()
            }
        }
        // "LATER" 操作不需要特别处理，因为它只是关闭通知
        
        completionHandler()
    }
    
    // 允许在应用在前台时显示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
