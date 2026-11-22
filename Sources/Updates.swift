import AppKit
#if SPARKLE_UPDATES
import Sparkle

@MainActor
final class InAppUpdater {
    let updater: SPUUpdater

    init() throws {
        let driver = ConfirmedUpdateDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        try updater.start()
    }
}

private final class ConfirmedUpdateDriver: SPUStandardUserDriver {
    private var approved = false

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showUpdateFound(with: appcastItem, state: state) { choice in
            self.approved = choice == .install
            reply(choice)
        }
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if approved {
            approved = false
            reply(.install)
        } else {
            super.showReady(toInstallAndRelaunch: reply)
        }
    }
}
#endif

enum Updates {
    static let releases = URL(string: "https://github.com/gokberkkaraca/BetterScroll/releases")!

    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }

    private struct Release: Decodable { let tag_name: String }

    @MainActor static func check() async {
        let alert = NSAlert()
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var link: URL?
        do {
            let endpoint = URL(string: "https://api.github.com/repos/gokberkkaraca/BetterScroll/releases/latest")!
            let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let tag = try JSONDecoder().decode(Release.self, from: data).tag_name
            guard tag.first == "v", let latest = components(String(tag.dropFirst())), let current = components(installed) else {
                throw URLError(.cannotParseResponse)
            }
            if current.lexicographicallyPrecedes(latest) {
                alert.messageText = "BetterScroll \(tag.dropFirst()) is available"
                alert.informativeText = "You have version \(installed). Open the release to download the update."
                link = releases.appendingPathComponent("tag").appendingPathComponent(tag)
            } else {
                alert.messageText = "BetterScroll is up to date"
                alert.informativeText = "Installed version \(installed). Latest release \(tag)."
            }
        } catch {
            alert.messageText = "Couldn’t check for updates"
            alert.informativeText = "Installed version \(installed). You can check the releases page in your browser."
            link = releases
        }
        if link != nil {
            alert.addButton(withTitle: "Open GitHub Releases")
            alert.addButton(withTitle: "Cancel")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let link { NSWorkspace.shared.open(link) }
    }
}
