import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder double-click, "Open With", `open -a`, and drag-onto-the-Dock-icon.
  ///
  /// File URLs are ours; anything else (a custom scheme a plugin registered
  /// for) goes to `super`. Splitting rather than always calling `super` keeps
  /// this the single path for a document: the base class may also hand the
  /// URL to the framework, and two routes opening one file is how a design
  /// ends up in two tabs.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingDocumentPlugin.shared.handle(urls: urls)
    let others = urls.filter { !$0.isFileURL }
    if !others.isEmpty {
      super.application(application, open: others)
    }
  }
}

/// Delivers documents macOS opens on NetCrux's behalf to Dart.
///
/// `Info.plist` declares NetCrux's document types, so Finder offers the app
/// for `.netcrux-project`, `.netcrux`, `.netcrux-workspace`, HDL sources,
/// filelists and `.crux-project` manifests, and a double-click launches it.
/// Without `application(_:open:)` the file itself was accepted and dropped,
/// and the app opened empty. The Dart half is `IncomingDocumentService`, which
/// routes each path exactly as the same path on the command line.
///
/// One method channel in both directions: Dart asks `getInitialDocument` at
/// startup, then sends `listen`, and each later document is delivered as an
/// `openDocument` call. The app is not sandboxed (see `Release.entitlements`),
/// so a path is directly readable: no security scope to hold, no copy to make.
final class IncomingDocumentPlugin: NSObject {
  static let shared = IncomingDocumentPlugin()

  private var channel: FlutterMethodChannel?

  /// Paths that arrived before Dart could take them.
  ///
  /// A cold launch delivers the document that caused it before Dart's
  /// `main()` has run, so without this buffer the case the feature exists
  /// for — double-clicking a project when NetCrux is not running — would be
  /// the one case that dropped it.
  private var pending: [String] = []

  /// Set while Dart is listening, so a document goes straight across
  /// instead of into the buffer.
  private var isListening = false

  private override init() {}

  /// Call from `MainFlutterWindow.awakeFromNib()`, once the engine exists.
  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.netcrux/incoming_document",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getInitialDocument":
        // Only the first: Dart opens it as the launch intent and takes the
        // rest when it starts listening, the same shape as several files on
        // the command line.
        result(self.pending.isEmpty ? nil : self.pending.removeFirst())
      case "listen":
        self.isListening = true
        let queued = self.pending
        self.pending.removeAll()
        result(nil)
        for path in queued {
          self.deliver(path)
        }
      case "cancel":
        self.isListening = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// Forwards each file URL; other URLs are not documents.
  func handle(urls: [URL]) {
    for url in urls where url.isFileURL {
      if isListening {
        deliver(url.path)
      } else {
        pending.append(url.path)
      }
    }
  }

  private func deliver(_ path: String) {
    channel?.invokeMethod("openDocument", arguments: path)
  }
}
