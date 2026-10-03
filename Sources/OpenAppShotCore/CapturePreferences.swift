import AppKit
import Foundation

public enum CapturePreferences {
    private static let defaults = UserDefaults.standard
    private static let captureDirectoryKey = "captureDirectoryPath"
    private static let storageContainerKey = "captureStorageContainerPath"
    private static let knownCaptureRootsKey = "knownCaptureRootPaths"
    private static let retentionDaysKey = "captureRetentionDays"
    private static let copyAfterCaptureKey = "copyAfterCapture"
    private static let legacyPlaySoundKey = "playCaptureSound"
    private static let captureSoundKey = "captureSoundName"
    private static let captureHotkeyKey = "captureHotkey"
    private static let confirmBeforeDeletingKey = "confirmBeforeDeleting"
    private static let clipboardModeKey = "clipboardMode"

    public static var defaultCaptureRootURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return
            applicationSupport
            .appendingPathComponent("Open AppShot", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    public static var legacyCaptureRootURL: URL {
        URL(fileURLWithPath: "/tmp/AppShotClipboardPOC", isDirectory: true)
    }

    public static var captureRootURL: URL {
        guard let path = defaults.string(forKey: storageContainerKey), !path.isEmpty else {
            return defaultCaptureRootURL
        }
        return URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("Open AppShot", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    public static var storageContainerPath: String? {
        defaults.string(forKey: storageContainerKey)
    }

    public static var knownCaptureRootURLs: [URL] {
        let stored = defaults.stringArray(forKey: knownCaptureRootsKey) ?? []
        return uniqueURLs(
            stored.map { URL(fileURLWithPath: $0, isDirectory: true) }
                + [defaultCaptureRootURL, captureRootURL]
        )
    }

    public static func selectStorageContainer(_ path: String?) {
        rememberCaptureRoot(captureRootURL)
        if let path, !path.isEmpty {
            defaults.set(path, forKey: storageContainerKey)
        } else {
            defaults.removeObject(forKey: storageContainerKey)
        }
        rememberCaptureRoot(captureRootURL)
    }

    public static var storageContainerURL: URL? {
        storageContainerPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public static var legacyCustomCaptureRootURL: URL? {
        guard let path = defaults.string(forKey: captureDirectoryKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func rememberCaptureRoot(_ root: URL) {
        let paths = uniqueURLs(
            (defaults.stringArray(forKey: knownCaptureRootsKey) ?? [])
                .map { URL(fileURLWithPath: $0, isDirectory: true) } + [root]
        ).map(\.path)
        defaults.set(paths, forKey: knownCaptureRootsKey)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    public static var retentionDays: Int {
        get {
            guard defaults.object(forKey: retentionDaysKey) != nil else { return 30 }
            return defaults.integer(forKey: retentionDaysKey)
        }
        set { defaults.set(newValue, forKey: retentionDaysKey) }
    }

    public static var copyAfterCapture: Bool {
        get {
            guard defaults.object(forKey: copyAfterCaptureKey) != nil else { return true }
            return defaults.bool(forKey: copyAfterCaptureKey)
        }
        set { defaults.set(newValue, forKey: copyAfterCaptureKey) }
    }

    public static var captureSound: CaptureSound {
        get {
            if let stored = defaults.string(forKey: captureSoundKey), let sound = CaptureSound(rawValue: stored) {
                return sound
            }
            if defaults.object(forKey: legacyPlaySoundKey) != nil, !defaults.bool(forKey: legacyPlaySoundKey) {
                return .none
            }
            return .glass
        }
        set { defaults.set(newValue.rawValue, forKey: captureSoundKey) }
    }

    public static var captureHotkey: CaptureHotkey {
        get {
            guard let data = defaults.data(forKey: captureHotkeyKey),
                let hotkey = try? JSONDecoder().decode(CaptureHotkey.self, from: data),
                CaptureHotkey.isAllowed(hotkey)
            else { return .dualOption }
            return hotkey
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: captureHotkeyKey)
        }
    }

    public static var confirmBeforeDeleting: Bool {
        get {
            guard defaults.object(forKey: confirmBeforeDeletingKey) != nil else { return true }
            return defaults.bool(forKey: confirmBeforeDeletingKey)
        }
        set { defaults.set(newValue, forKey: confirmBeforeDeletingKey) }
    }

    public static var clipboardMode: ClipboardMode {
        get {
            guard let stored = defaults.string(forKey: clipboardModeKey),
                let mode = ClipboardMode(rawValue: stored)
            else { return .imageAndFullContext }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: clipboardModeKey) }
    }

}
