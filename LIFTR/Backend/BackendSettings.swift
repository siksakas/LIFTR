//
//  BackendSettings.swift
//  LIFTR
//

import Foundation

/// Where the Liftr backend (the `backend/` folder) is running, read from `Backend.plist` in the app
/// bundle, or from a URL pasted into the Coach tab's setup card.
///
/// The backend holds every API key (Snowflake, DigitalOcean, ElevenLabs). The app only knows its URL.
/// Copy `Config/Backend.example.plist` to `LIFTR/Backend.plist` (gitignored) and fill it in.
struct BackendSettings {
    /// For example `http://localhost:8080` in the simulator, or the DigitalOcean app's https URL.
    var baseURL: URL
    /// Optional. Must match `APP_TOKEN` in the backend's environment if that is set.
    var appToken: String?

    /// UserDefaults key for a URL entered in the app instead of the plist.
    static let savedURLKey = "BackendBaseURL"
    private static let userIDKey = "BackendUserID"

    static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> BackendSettings? {
        fromPlist(in: bundle) ?? defaults.string(forKey: savedURLKey)
            .flatMap(normalizedURL)
            .map { BackendSettings(baseURL: $0, appToken: nil) }
    }

    /// Trims the URL and rejects anything that isn't an http or https address.
    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            url.host != nil
        else { return nil }
        return url
    }

    /// A random ID made on first launch, so the backend can tell this install's logs apart.
    /// Not a login: anyone who learns it can read this install's data, which is fine for a hackathon demo.
    static var userID: String {
        if let id = UserDefaults.standard.string(forKey: userIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: userIDKey)
        return id
    }

    private static func fromPlist(in bundle: Bundle) -> BackendSettings? {
        guard
            let url = bundle.url(forResource: "Backend", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let baseURL = (plist["BaseURL"] as? String).flatMap(normalizedURL)
        else { return nil }

        let token = (plist["AppToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BackendSettings(baseURL: baseURL, appToken: token?.isEmpty == false ? token : nil)
    }
}
