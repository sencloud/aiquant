import CoreTelephony
import Flutter
import MapKit
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

    // 喜爱钓鱼「钓点地图」：系统 MapKit 平台视图（免费、无需 key；大陆境内是合规底图）。
    if let registrar = self.registrar(forPlugin: "XiaiFishingMap") {
      registrar.register(
        FishingMapFactory(messenger: registrar.messenger()),
        withId: "xiai/fishing_map"
      )
    }

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

// MARK: - 钓点地图（MapKit 平台视图）

/// Dart 侧 `FishingMap`（lib/topics/fishing/map/fishing_map.dart）对应的原生视图。
///
/// 坐标约定：这里收发的都是「地图坐标」—— 大陆境内即 GCJ-02（MapKit 底图坐标系），
/// WGS-84 ↔ GCJ-02 的换算全部在 Dart 侧做，原生侧不碰坐标系。
/// 我的位置由 MapKit 自己画（showsUserLocation），只在 Dart 侧确认已授权后打开；
/// 这里不申请定位权限、不读取位置。
final class FishingMapFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return FishingMapPlatformView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

final class FishingSpotAnnotation: MKPointAnnotation {
  var spotId: String = ""
}

final class FishingMapPlatformView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let mapView: MKMapView
  private let channel: FlutterMethodChannel
  private var tint: UIColor = UIColor(red: 0.12, green: 0.42, blue: 0.48, alpha: 1)

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    mapView = MKMapView(frame: frame)
    channel = FlutterMethodChannel(name: "xiai/fishing_map/\(viewId)", binaryMessenger: messenger)
    super.init()

    if let argb = (args["tint"] as? NSNumber)?.uint32Value {
      tint = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: 1
      )
    }
    mapView.delegate = self
    mapView.showsCompass = true
    mapView.showsScale = true
    mapView.pointOfInterestFilter = .excludingAll
    mapView.showsUserLocation = (args["showsUser"] as? Bool) ?? false
    if let lat = (args["lat"] as? NSNumber)?.doubleValue,
       let lon = (args["lon"] as? NSNumber)?.doubleValue {
      let span = (args["span"] as? NSNumber)?.doubleValue ?? 8000
      mapView.setRegion(
        MKCoordinateRegion(
          center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
          latitudinalMeters: span,
          longitudinalMeters: span
        ),
        animated: false
      )
    }
    setSpots(args["spots"] as? [[String: Any]] ?? [])

    let press = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
    press.minimumPressDuration = 0.5
    mapView.addGestureRecognizer(press)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return mapView
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setSpots":
      setSpots(call.arguments as? [[String: Any]] ?? [])
      result(nil)
    case "setShowsUser":
      mapView.showsUserLocation = (call.arguments as? Bool) ?? false
      result(nil)
    case "moveTo":
      let a = call.arguments as? [String: Any] ?? [:]
      guard let lat = (a["lat"] as? NSNumber)?.doubleValue,
            let lon = (a["lon"] as? NSNumber)?.doubleValue else {
        result(nil)
        return
      }
      let span = (a["span"] as? NSNumber)?.doubleValue ?? 4000
      mapView.setRegion(
        MKCoordinateRegion(
          center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
          latitudinalMeters: span,
          longitudinalMeters: span
        ),
        animated: true
      )
      result(nil)
    case "center":
      let c = mapView.centerCoordinate
      result([c.latitude, c.longitude])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setSpots(_ spots: [[String: Any]]) {
    let old = mapView.annotations.compactMap { $0 as? FishingSpotAnnotation }
    mapView.removeAnnotations(old)
    var added: [FishingSpotAnnotation] = []
    for s in spots {
      guard let id = s["id"] as? String,
            let lat = (s["lat"] as? NSNumber)?.doubleValue,
            let lon = (s["lon"] as? NSNumber)?.doubleValue else { continue }
      let a = FishingSpotAnnotation()
      a.spotId = id
      a.title = s["name"] as? String
      let sub = s["subtitle"] as? String ?? ""
      a.subtitle = sub.isEmpty ? nil : sub
      a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      added.append(a)
    }
    mapView.addAnnotations(added)
  }

  @objc private func onLongPress(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began else { return }
    let c = mapView.convert(g.location(in: mapView), toCoordinateFrom: mapView)
    channel.invokeMethod("longPress", arguments: ["lat": c.latitude, "lon": c.longitude])
  }

  // MARK: MKMapViewDelegate

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard annotation is FishingSpotAnnotation else { return nil }
    let id = "fishing-spot"
    let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
      ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
    v.annotation = annotation
    v.markerTintColor = tint
    if #available(iOS 16.0, *) {
      v.glyphImage = UIImage(systemName: "fish.fill")
    } else {
      v.glyphImage = UIImage(systemName: "mappin")
    }
    v.titleVisibility = .visible
    v.subtitleVisibility = .hidden
    v.canShowCallout = false
    return v
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let a = view.annotation as? FishingSpotAnnotation else { return }
    channel.invokeMethod("spotTap", arguments: ["id": a.spotId])
    mapView.deselectAnnotation(a, animated: false)
  }
}
