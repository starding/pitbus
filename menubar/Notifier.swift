import AppKit
import UserNotifications

/// Notifications from pit, posted under PitBus's own name and icon. The daemon drops each one as a JSON file in
/// <data>/notify; this watches the folder, posts what lands there and removes it. A click opens its link.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    let dir = URL(fileURLWithPath: dataDir + "/notify")
    var open: ((String) -> Void)?
    private var watch: DispatchSourceFileSystemObject?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watch = src
        drain()  // what came while the app was not running
    }

    private func drain() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            defer { try? FileManager.default.removeItem(at: f) }
            guard let data = try? Data(contentsOf: f),
                  let n = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let c = UNMutableNotificationContent()
            c.title = n["title"] as? String ?? "PitBus"
            c.body = n["text"] as? String ?? ""
            c.sound = .default
            if let link = n["link"] as? String { c.userInfo = ["link": link] }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: f.lastPathComponent, content: c, trigger: nil))
        }
    }

    // shown even while PitBus is the active app (the panel is open)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let link = response.notification.request.content.userInfo["link"] as? String { open?(link) }
        done()
    }
}
