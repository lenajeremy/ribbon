import AppKit
import Security
import SwiftUI

/// Keeps Ribbon up to date from its GitHub releases. A release is tagged like v3.1, has Ribbon.zip attached,
/// and its notes are the changelog. A download is installed only if it's signed with the same Developer ID
/// team as this copy, so nobody else can ship Ribbon an update.
@Observable @MainActor final class Updater {
    struct Release: Identifiable, Equatable {
        let version: String
        let notes: String
        let date: Date?
        let page: URL
        let download: URL?
        var id: String { version }
    }

    enum Phase: Equatable { case idle, checking, downloading, ready, failed(String) }

    nonisolated static let releasesFeed = URL(string: "https://api.github.com/repos/lenajeremy/ribbon/releases?per_page=20")!
    nonisolated static let releasesPage = URL(string: "https://github.com/lenajeremy/ribbon/releases")!
    nonisolated static let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private(set) var phase: Phase = .idle
    /// Versions newer than this copy, newest first.
    private(set) var newer: [Release] = []
    /// This copy's own release, for "What's new" when you're up to date.
    private(set) var installed: Release?
    private(set) var lastChecked: Date? { didSet { defaults.set(lastChecked, forKey: "lastUpdateCheck") } }
    var latest: Release? { newer.first }

    /// True while a focus session runs: the alert waits, and restarting is put off until it ends.
    @ObservationIgnored var isBusy: () -> Bool = { false }
    /// Where releases are listed, and the app that gets replaced. Tests point these somewhere else.
    @ObservationIgnored var feed = Updater.releasesFeed
    @ObservationIgnored var target = Bundle.main.bundleURL
    @ObservationIgnored let settings: Settings
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var staged: (app: URL, version: String)?
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var alertWaiting = false

    init(settings: Settings) {
        self.settings = settings
        lastChecked = defaults.object(forKey: "lastUpdateCheck") as? Date
    }

    /// Checks shortly after launch, then every six hours.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in Task { await self?.check() } }
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.check() } }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Looks for a newer version. With automatic updates on, it's downloaded before you're told about it.
    /// `userInitiated` (Check for Updates…) opens the window straight away and shows the result there.
    func check(userInitiated: Bool = false) async {
        if userInitiated { showWindow() }
        guard phase != .checking, phase != .downloading else { return }
        phase = .checking
        do {
            let releases = try await Self.fetchReleases(from: feed)
            lastChecked = Date()
            newer = releases.filter { Self.isNewer($0.version, than: Self.current) }
            installed = releases.first { $0.version == Self.current }
            phase = staged != nil && staged?.version == latest?.version ? .ready : .idle
            logLine("Updates: " + (latest.map { "Ribbon \($0.version) is available" } ?? "up to date at \(Self.current)"))
        } catch {
            phase = .failed("Ribbon couldn't reach GitHub to check for updates. Check your internet connection and try again.")
            logLine("Updates: check failed: \(error.localizedDescription)")
            return
        }
        guard let latest else { return }
        if settings.automaticUpdates && phase != .ready { await download(latest) }
        guard !userInitiated else { return }  // The window is already open.
        // Each version gets one alert: when it's ready to install, or, with automatic updates off, when it's out.
        guard defaults.string(forKey: "announcedUpdate") != latest.version else { return }
        defaults.set(latest.version, forKey: "announcedUpdate")
        if isBusy() { alertWaiting = true } else { showWindow() }
    }

    /// Downloads a release and checks it's genuine. It's installed when you restart or quit Ribbon.
    func download(_ release: Release) async {
        guard let url = release.download else {
            phase = .failed("This version can't be installed from inside Ribbon. Download it from GitHub instead.")
            return
        }
        guard canReplace else {
            phase = .failed("Move Ribbon to your Applications folder so it can update itself, or download the new version from GitHub.")
            return
        }
        phase = .downloading
        do {
            guard let team = Self.teamIdentifier(), let identifier = Bundle(url: target)?.bundleIdentifier else {
                throw UpdateError("This copy of Ribbon isn't signed, so it can't check that an update is genuine. Download it from GitHub instead.")
            }
            let app = try await Self.fetch(url, next: target)
            try Self.verify(app, version: release.version, identifier: identifier, team: team)
            staged = (app, release.version)
            phase = .ready
            logLine("Updates: Ribbon \(release.version) downloaded and verified")
        } catch {
            phase = .failed((error as? UpdateError)?.message ?? "The download didn't finish. \(error.localizedDescription)")
            logLine("Updates: download failed: \(error.localizedDescription)")
        }
    }

    /// Puts the downloaded version in place of this one. It runs from the next launch.
    @discardableResult func installStaged() -> Bool {
        guard let staged else { return false }
        self.staged = nil
        // The system may have cleared the download from its temporary folder.
        guard FileManager.default.fileExists(atPath: staged.app.path) else { phase = .idle; return false }
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged.app, backupItemName: nil, options: .usingNewMetadataOnly)
            logLine("Updates: installed Ribbon \(staged.version)")
            return true
        } catch {
            phase = .failed("Ribbon couldn't replace itself in \(target.deletingLastPathComponent().path). Download the new version from GitHub instead.")
            logLine("Updates: install failed: \(error.localizedDescription)")
            return false
        }
    }

    func restartNow() {
        guard !isBusy(), installStaged() else { return }
        relaunch()
    }

    /// A ready update is installed as Ribbon quits, so the next launch is the new version.
    func applicationWillQuit() { installStaged() }

    /// Shows an alert that waited for a focus session to end.
    func focusEnded() {
        guard alertWaiting, !isBusy() else { return }
        alertWaiting = false
        showWindow()
    }

    private var canReplace: Bool {
        !target.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    // MARK: The window

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            let host = NSHostingController(rootView: UpdateView(updater: self) { [weak window] in window?.close() })
            host.sizingOptions = [.minSize, .maxSize]
            window.contentViewController = host
            window.setContentSize(host.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: GitHub

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let published_at: Date?
        let html_url: URL
        let assets: [Asset]
    }

    nonisolated static func fetchReleases(from feed: URL) async throws -> [Release] {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ribbon/\(current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubRelease].self, from: data)
            .filter { !$0.draft && !$0.prerelease }
            .map { release in
                Release(version: release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name,
                        notes: (release.body ?? "").replacingOccurrences(of: "\r\n", with: "\n"),
                        date: release.published_at, page: release.html_url,
                        download: release.assets.first { $0.name == "Ribbon.zip" }?.browser_download_url)
            }
            .sorted { isNewer($0.version, than: $1.version) }
    }

    /// Downloads Ribbon.zip and unpacks it on the same disk as `next`, so swapping it in is a rename.
    nonisolated static func fetch(_ url: URL, next: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download failed. Try again later.") }
        let fileManager = FileManager.default
        let folder = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: next, create: true)
        let zip = folder.appendingPathComponent("Ribbon.zip")
        try fileManager.moveItem(at: file, to: zip)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        try? fileManager.removeItem(at: zip)
        let app = folder.appendingPathComponent("Ribbon.app")
        guard unzip.terminationStatus == 0, fileManager.fileExists(atPath: app.path) else {
            throw UpdateError("The download was damaged. Try again later.")
        }
        return app
    }

    /// The new app must be this app, the expected version, and signed with a Developer ID from the same team.
    nonisolated static func verify(_ app: URL, version: String, identifier: String, team: String) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == identifier, info?["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError("The download isn't the expected version of Ribbon, so it wasn't installed.")
        }
        let rule = "anchor apple generic and identifier \"\(identifier)\" and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"\(team)\""
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
        else { throw UpdateError("The download isn't signed by Ribbon's developer, so it wasn't installed.") }
    }

    /// The team that signed this copy of Ribbon, or nil when it isn't signed by a developer.
    nonisolated static func teamIdentifier() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Compares dotted versions number by number: 3.10 is newer than 3.9.
    nonisolated static func isNewer(_ version: String, than other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }, b = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The update alert: which version is out, what's in it, and a button to restart into it.
struct UpdateView: View {
    let updater: Updater
    let close: () -> Void

    var body: some View {
        @Bindable var settings = updater.settings
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }

            if !notes.isEmpty {
                Text(updater.latest == nil ? "What's new in this version" : "What's new")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 20).padding(.bottom, 8)
                // Short notes show in full; long ones scroll.
                ViewThatFits(in: .vertical) {
                    changelog
                    ScrollView { changelog }
                }
                .frame(maxHeight: 340, alignment: .top)
                .background(Theme.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            }

            HStack(spacing: 10) {
                Toggle("Install updates automatically", isOn: $settings.automaticUpdates)
                    .toggleStyle(.checkbox).font(.system(size: 12.5)).fixedSize()
                Spacer(minLength: 12)
                buttons
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.page)
        .foregroundStyle(Theme.ink)
    }

    private var changelog: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(notes) { release in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Ribbon \(release.version)").font(.system(size: 14, weight: .semibold))
                        if let date = release.date {
                            Text(date.formatted(date: .abbreviated, time: .omitted)).font(Typeface.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    MarkdownBlocks(text: release.notes)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notes: [Updater.Release] {
        if !updater.newer.isEmpty { return updater.newer.filter { !$0.notes.isEmpty } }
        return updater.installed.map { $0.notes.isEmpty ? [] : [$0] } ?? []
    }

    private var title: String {
        guard let latest = updater.latest else {
            switch updater.phase {
            case .checking: return "Checking for updates…"
            case .failed: return "Couldn't check for updates"
            default: return "Ribbon is up to date"
            }
        }
        switch updater.phase {
        case .ready: return "Ribbon \(latest.version) is ready to install"
        case .downloading: return "Downloading Ribbon \(latest.version)…"
        default: return "Ribbon \(latest.version) is available"
        }
    }

    private var subtitle: String {
        guard updater.latest != nil else {
            if case .failed(let message) = updater.phase { return message }
            return updater.phase == .checking ? "You have Ribbon \(Updater.current)." : "You have the newest version, Ribbon \(Updater.current)."
        }
        switch updater.phase {
        case .ready:
            return updater.isBusy() ? "Restart Ribbon after your focus session to finish updating, or it updates the next time Ribbon quits."
                : "Restart Ribbon to finish updating. If you choose Later, it updates the next time Ribbon quits."
        case .failed(let message): return message
        default: return "You have Ribbon \(Updater.current)."
        }
    }

    @ViewBuilder private var buttons: some View {
        if let latest = updater.latest {
            Button("Later", action: close).buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
            switch updater.phase {
            case .ready:
                Button("Restart Now") { updater.restartNow() }
                    .buttonStyle(PillButtonStyle(primary: true)).keyboardShortcut(.defaultAction).disabled(updater.isBusy())
            case .downloading, .checking:
                Button {} label: {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(updater.phase == .checking ? "Checking" : "Downloading") }
                }
                .buttonStyle(PillButtonStyle(primary: true)).disabled(true)
            case .failed:
                Button("View on GitHub") { NSWorkspace.shared.open(latest.page); close() }
                    .buttonStyle(PillButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            case .idle:
                Button("Install Update") { Task { await updater.download(latest) } }
                    .buttonStyle(PillButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        } else {
            Button(updater.phase == .checking ? "Cancel" : "Done", action: close)
                .buttonStyle(PillButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        }
    }
}
