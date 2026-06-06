import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.promptAccessibility()
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }
}
