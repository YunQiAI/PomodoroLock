import Foundation
import UserNotifications

// 通知响应代理类
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    private override init() {
        super.init()
    }
    
    // 当用户响应通知时调用
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // 处理用户对通知的响应
        switch response.actionIdentifier {
        case "START_POMODORO":
            // 用户选择开始新的番茄周期
            DispatchQueue.main.async {
                sharedPomodoroTimer.start()
            }
        default:
            // 用户选择稍后再说或者直接点击通知
            break
        }
        
        completionHandler()
    }
    
    // 应用在前台时如何处理通知
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 在前台仍然显示通知
        completionHandler([.banner, .sound, .list])
    }
}
