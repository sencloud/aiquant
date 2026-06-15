import CoreTelephony
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Dart 侧 PushRegistrationService 监听的 channel。
  private static let channelName = "cn.singzquant.aiquant/push"
  // Dart 侧 NetworkPermissionService 监听的 channel：蜂窝/无线数据授权状态。
  private static let networkChannelName = "cn.singzquant.aiquant/network"

  private var pushChannel: FlutterMethodChannel?
  private var cachedToken: String?

  private var networkChannel: FlutterMethodChannel?
  private let cellularData = CTCellularData()
  // 记录上一次的受限状态，仅在「未知/受限 → 可用」的真实变化时通知 Dart，
  // 避免冷启动即已授权或回调重复触发导致无意义刷新。
  private var lastCellularRestricted = true

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: AppDelegate.channelName,
        binaryMessenger: controller.binaryMessenger
      )
      pushChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterMethodNotImplemented)
          return
        }
        switch call.method {
        case "requestAndRegister":
          self.requestAndRegister(result: result)
        case "getCachedToken":
          result(self.cachedToken)
        case "setBadge":
          // 期望调用方传 { "count": Int }；缺省按 0 处理。
          let count = (call.arguments as? [String: Any])?["count"] as? Int ?? 0
          DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
              UNUserNotificationCenter.current().setBadgeCount(count)
            } else {
              UIApplication.shared.applicationIconBadgeNumber = count
            }
            result(nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let netChannel = FlutterMethodChannel(
        name: AppDelegate.networkChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      networkChannel = netChannel
      netChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterMethodNotImplemented)
          return
        }
        switch call.method {
        case "getCellularState":
          result(self.cellularStateString(self.cellularData.restrictedState))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      observeCellularData()
    }

    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Cellular / Wi-Fi Data Permission

  /// 监听系统「无线数据」授权状态。用户在首启弹窗里选择「WLAN 与蜂窝网络」或
  /// 「仅蜂窝网络」后，restrictedState 会从 unknown/restricted 变为 notRestricted，
  /// 此时通知 Dart 自动重新联网并刷新页面。
  private func observeCellularData() {
    lastCellularRestricted = (cellularData.restrictedState != .notRestricted)
    cellularData.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
      guard let self = self else { return }
      let nowRestricted = (state != .notRestricted)
      let becameAvailable = self.lastCellularRestricted && !nowRestricted
      self.lastCellularRestricted = nowRestricted
      guard becameAvailable else { return }
      DispatchQueue.main.async {
        self.networkChannel?.invokeMethod("onNetworkAvailable", arguments: nil)
      }
    }
  }

  private func cellularStateString(_ state: CTCellularDataRestrictedState) -> String {
    switch state {
    case .notRestricted: return "notRestricted"
    case .restricted: return "restricted"
    default: return "unknown"
    }
  }

  // MARK: - APNs Registration

  private func requestAndRegister(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async {
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    cachedToken = token
    pushChannel?.invokeMethod("onApnsToken", arguments: token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pushChannel?.invokeMethod("onApnsError", arguments: error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // MARK: - Foreground Presentation

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
