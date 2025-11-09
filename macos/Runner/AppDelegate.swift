import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var bookmarkSessions: [String: NSURL] = [:]

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "sftp_sync_manager/macos_bookmarks",
        binaryMessenger: controller.engine.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "NO_DELEGATE", message: "AppDelegate released", details: nil))
          return
        }
        switch call.method {
        case "pickDirectory":
          self.handlePickDirectory(call: call, result: result)
        case "startAccess":
          self.handleStartAccess(call: call, result: result)
        case "stopAccess":
          self.handleStopAccess(call: call, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func handlePickDirectory(call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = false
      panel.prompt = "选择"

      if
        let args = call.arguments as? [String: Any],
        let initialDirectory = args["initialDirectory"] as? String,
        !initialDirectory.isEmpty
      {
        panel.directoryURL = URL(fileURLWithPath: initialDirectory, isDirectory: true)
      }

      panel.begin { response in
        if response == .OK, let url = panel.url {
          do {
            let data = try url.bookmarkData(
              options: NSURL.BookmarkCreationOptions.withSecurityScope,
              includingResourceValuesForKeys: nil,
              relativeTo: nil
            )
            let bookmark = data.base64EncodedString()
            result(["path": url.path, "bookmark": bookmark])
          } catch {
            result(
              FlutterError(
                code: "BOOKMARK_CREATE_FAILED",
                message: "Failed to create bookmark: \(error.localizedDescription)",
                details: nil
              )
            )
          }
        } else {
          result(nil)
        }
      }
    }
  }

  private func handleStartAccess(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let bookmark = args["bookmark"] as? String,
      let data = Data(base64Encoded: bookmark)
    else {
      result(FlutterError(code: "BOOKMARK_INVALID", message: "Invalid bookmark data", details: nil))
      return
    }

    do {
      var isStale = ObjCBool(false)
      let url = try NSURL(
        resolvingBookmarkData: data,
        options: [NSURL.BookmarkResolutionOptions.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale.boolValue {
        // Attempt to refresh stale bookmark to avoid future failures
        _ = try url.bookmarkData(
          options: NSURL.BookmarkCreationOptions.withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      }

      guard url.startAccessingSecurityScopedResource() else {
        result(
          FlutterError(
            code: "BOOKMARK_START_FAILED",
            message: "Unable to access security scoped resource",
            details: nil
          )
        )
        return
      }

      let handle = UUID().uuidString
      bookmarkSessions[handle] = url
      result(handle)
    } catch {
      result(
        FlutterError(
          code: "BOOKMARK_RESOLVE_FAILED",
          message: "Failed to resolve bookmark: \(error.localizedDescription)",
          details: nil
        )
      )
    }
  }

  private func handleStopAccess(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let handle = args["handle"] as? String
    else {
      result(nil)
      return
    }

    if let url = bookmarkSessions.removeValue(forKey: handle) {
      url.stopAccessingSecurityScopedResource()
    }
    result(nil)
  }
}
