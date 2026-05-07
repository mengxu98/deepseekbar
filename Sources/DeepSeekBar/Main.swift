import AppKit

@main
enum DeepSeekBarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = DeepSeekBarApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
