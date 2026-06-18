import Foundation

enum AppInfo {
    static let repoOwner = "ProjectMakersDE"
    static let repoName = "MacZones"

    /// Marketing version from the bundle's Info.plist (falls back to "dev" when
    /// run unbundled via `swift run`).
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }
    static var releasesPage: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    }
}
