import AppKit

/// Fires whenever the frontmost application changes.
final class FrontmostAppObserver {
    private var token: NSObjectProtocol?
    var onChange: ((NSRunningApplication?) -> Void)?

    func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onChange?(app)
        }
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
