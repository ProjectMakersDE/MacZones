import Cocoa

/// Checks GitHub Releases for a newer version and, on request, downloads the
/// `.zip` asset and swaps the running app bundle in place. One-shot network
/// calls only — no background polling.
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release {
        let version: String       // without a leading "v"
        let zipURL: URL?
        let pageURL: URL
    }

    // MARK: Public entry points

    /// Manual check from the menu — always shows a result dialog.
    func checkManually() {
        check { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                self.alert(title: "Update-Prüfung fehlgeschlagen",
                           text: "Die neueste Version konnte nicht abgerufen werden. Bitte später erneut versuchen.",
                           style: .warning)
            case .success(let release):
                if UpdateChecker.isNewer(release.version, than: AppInfo.version) {
                    self.promptInstall(release)
                } else {
                    self.alert(title: "MacZones ist aktuell",
                               text: "Du verwendest bereits Version \(AppInfo.version).",
                               style: .informational)
                }
            }
        }
    }

    /// Quiet check used at launch — reports a newer release (or nil) without UI.
    func checkSilently(_ completion: @escaping (Release?) -> Void) {
        check { result in
            if case .success(let release) = result,
               UpdateChecker.isNewer(release.version, than: AppInfo.version) {
                DispatchQueue.main.async { completion(release) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: Networking

    private func check(_ completion: @escaping (Result<Release, Error>) -> Void) {
        var req = URLRequest(url: AppInfo.latestReleaseAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MacZones", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            var zipURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for a in assets {
                    if let name = a["name"] as? String, name.hasSuffix(".zip"),
                       let urlStr = a["browser_download_url"] as? String, let url = URL(string: urlStr) {
                        zipURL = url
                        break
                    }
                }
            }
            let page = (json["html_url"] as? String).flatMap(URL.init) ?? AppInfo.releasesPage
            DispatchQueue.main.async {
                completion(.success(Release(version: version, zipURL: zipURL, pageURL: page)))
            }
        }.resume()
    }

    // MARK: Install

    private func promptInstall(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Update verfügbar: MacZones \(release.version)"
        alert.informativeText = """
        Installiert: \(AppInfo.version)

        Jetzt herunterladen und installieren? MacZones startet anschließend neu. \
        Die Bedienungshilfen-Berechtigung bleibt erhalten (gleiches Signaturzertifikat).
        """
        alert.addButton(withTitle: "Installieren")
        alert.addButton(withTitle: "Auf GitHub öffnen")
        alert.addButton(withTitle: "Abbrechen")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let zip = release.zipURL {
                downloadAndInstall(zip)
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private func downloadAndInstall(_ zipURL: URL) {
        URLSession.shared.downloadTask(with: zipURL) { [weak self] tmp, _, error in
            guard let self = self else { return }
            guard let tmp = tmp, error == nil else {
                DispatchQueue.main.async {
                    self.alert(title: "Download fehlgeschlagen",
                               text: error?.localizedDescription ?? "Unbekannter Fehler.",
                               style: .warning)
                }
                return
            }
            do {
                try self.installFromZip(at: tmp)
            } catch {
                DispatchQueue.main.async {
                    self.alert(title: "Installation fehlgeschlagen",
                               text: error.localizedDescription, style: .warning)
                }
            }
        }.resume()
    }

    private func installFromZip(at zip: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("MacZonesUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // Unzip with ditto (handles the macOS zip layout).
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw err("Das Archiv konnte nicht entpackt werden.")
        }

        let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "app" }
        guard let newApp = newApp else { throw err("Im Archiv wurde keine App gefunden.") }

        let dest = Bundle.main.bundlePath
        let destParent = (dest as NSString).deletingLastPathComponent
        guard fm.isWritableFile(atPath: destParent) else {
            DispatchQueue.main.async {
                self.alert(title: "Kein Schreibzugriff",
                           text: "MacZones liegt in „\(destParent)“ und kann dort nicht ersetzt werden. "
                               + "Bitte die App nach „Programme“ verschieben oder das Update manuell installieren.",
                           style: .warning)
                NSWorkspace.shared.open(AppInfo.releasesPage)
            }
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        NEW="\(dest).new"
        /bin/rm -rf "$NEW"
        if /usr/bin/ditto "\(newApp.path)" "$NEW"; then
          /bin/rm -rf "\(dest)"
          /bin/mv "$NEW" "\(dest)"
          /usr/bin/xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null
        fi
        /usr/bin/open "\(dest)"
        """
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/bash")
        swap.arguments = [scriptURL.path]
        try swap.run()   // independent child; keeps running after we quit

        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: Helpers

    private func err(_ message: String) -> NSError {
        NSError(domain: "MacZones", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func alert(title: String, text: String, style: NSAlert.Style) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        a.runModal()
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            let trimmed = s.hasPrefix("v") ? String(s.dropFirst()) : s
            return trimmed.split(separator: ".").map { comp in
                Int(comp.prefix { $0.isNumber }) ?? 0
            }
        }
        let r = parts(remote)
        let l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
