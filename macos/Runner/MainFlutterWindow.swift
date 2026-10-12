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
    // Reopen where the user left it. AppKit saves the frame under this name
    // on every move and resize, and restores it here; a first launch keeps
    // the XIB's 800x600. Without it every launch opened at 800x600.
    _ = self.setFrameUsingName("MainWindow")
    self.setFrameAutosaveName("MainWindow")

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
