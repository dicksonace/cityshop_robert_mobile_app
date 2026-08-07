import Flutter
import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?
  private var channel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "CityShopDocumentPicker")?.messenger()
      ?? engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(name: "cityshop/document_picker", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickDocument" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentDocumentPicker(result: result)
    }
  }

  private func presentDocumentPicker(result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "busy", message: "A file picker is already open.", details: nil))
      return
    }
    pendingResult = result

    var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .rtf, .zip]
    if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
    if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
    if let xls = UTType(filenameExtension: "xls") { types.append(xls) }
    if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
    if let ppt = UTType(filenameExtension: "ppt") { types.append(ppt) }
    if let pptx = UTType(filenameExtension: "pptx") { types.append(pptx) }
    if let rar = UTType(filenameExtension: "rar") { types.append(rar) }
    if let odt = UTType(filenameExtension: "odt") { types.append(odt) }
    if let ods = UTType(filenameExtension: "ods") { types.append(ods) }

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false

    guard let controller = topViewController() else {
      pendingResult = nil
      result(FlutterError(code: "no_ui", message: "Could not open file picker.", details: nil))
      return
    }
    controller.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    defer { pendingResult = nil }
    guard let result = pendingResult else { return }
    guard let url = urls.first else {
      result(nil)
      return
    }

    let name = url.lastPathComponent
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    result([
      "path": url.path,
      "name": name,
      "size": size,
      "mime": mime as Any,
    ])
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  private func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let base = base
      ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController
    if let nav = base as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = base as? UITabBarController {
      return topViewController(base: tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }
}
