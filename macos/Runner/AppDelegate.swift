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

  /// Finder double-click, "Open With", `open -a`, drag-onto-the-Dock-icon,
  /// and `netcrux://` links (the scheme `Info.plist` declares under
  /// `CFBundleURLTypes`).
  ///
  /// File URLs and `netcrux:` links are ours; anything else (a custom scheme
  /// a plugin registered for) goes to `super`. Splitting rather than always
  /// calling `super` keeps this the single path for a document: the base
  /// class may also hand the URL to the framework, and two routes opening one
  /// file is how a design ends up in two tabs.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingDocumentPlugin.shared.handle(urls: urls)
    IncomingLinkPlugin.shared.handle(urls: urls)
    let others = urls.filter { !$0.isFileURL && !IncomingLinkPlugin.isLink($0) }
    if !others.isEmpty {
      super.application(application, open: others)
    }
  }
}

/// Delivers `netcrux://` links to Dart, exactly as the system handed them
/// over.
///
/// Nothing here parses, decodes or trusts a link: it is forwarded as its
/// string and the Dart side (`lib/services/links/`) refuses anything that is
/// not a well-formed link to a design. A link that arrives before Dart is
/// listening (the link that launched the app) waits in a small buffer and is
/// delivered when Dart sends `listen`. The buffer keeps the newest few: a
/// burst of links at launch cannot grow it without bound, and Dart handles
/// one link at a time anyway.
///
/// One method channel in both directions, as for documents: Dart sends
/// `listen` and `cancel`, and each link is delivered as an `openLink` call.
final class IncomingLinkPlugin: NSObject {
  static let shared = IncomingLinkPlugin()

  /// The longest link forwarded. Dart refuses anything over an eighth of this
  /// with a message; past this the string is dropped here.
  private static let maxLength = 65536

  /// How many links wait for Dart to listen.
  private static let maxPending = 4

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var isListening = false

  private override init() {}

  /// Whether [url] uses the `netcrux` scheme, in any case.
  static func isLink(_ url: URL) -> Bool {
    return url.scheme?.lowercased() == "netcrux"
  }

  /// Call from `MainFlutterWindow.awakeFromNib()`, once the engine exists.
  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.netcrux/incoming_link",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "listen":
        self.isListening = true
        let queued = self.pending
        self.pending.removeAll()
        result(nil)
        for link in queued {
          self.deliver(link)
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

  /// Forwards each `netcrux:` URL; every other URL is someone else's.
  func handle(urls: [URL]) {
    for url in urls where IncomingLinkPlugin.isLink(url) {
      let link = url.absoluteString
      guard !link.isEmpty, link.count <= IncomingLinkPlugin.maxLength else { continue }
      if isListening {
        deliver(link)
      } else {
        pending.append(link)
        if pending.count > IncomingLinkPlugin.maxPending {
          pending.removeFirst(pending.count - IncomingLinkPlugin.maxPending)
        }
      }
    }
  }

  private func deliver(_ link: String) {
    channel?.invokeMethod("openLink", arguments: link)
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
