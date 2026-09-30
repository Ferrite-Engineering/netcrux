import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowAttentionPlugin: WindowAttentionPlugin?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 800, height: 500)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // CXP cross-probe attention: the native side of the portable
    // request-attention primitive (dock bounce, never a focus steal).
    windowAttentionPlugin = WindowAttentionPlugin(
      messenger: flutterViewController.engine.binaryMessenger)
    // The channel a Finder double-click is delivered on. The singleton holds
    // anything that arrived before now, which on a cold launch is the
    // document that caused the launch.
    IncomingDocumentPlugin.shared.register(
      with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
