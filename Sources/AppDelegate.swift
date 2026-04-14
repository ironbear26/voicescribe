import AppKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Menu bar only, no dock icon
        statusBarController = StatusBarController()
        statusBarController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController.cleanup()
    }
}
