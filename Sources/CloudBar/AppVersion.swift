import Foundation

enum AppVersion {
    static var shortVersion: String {
        versionInfo.shortVersion
    }

    static var build: String {
        versionInfo.build
    }

    static var displayString: String {
        "Version \(shortVersion) (\(build))"
    }

    private static let versionInfo: (shortVersion: String, build: String) = {
        if let info = Bundle.main.infoDictionary,
           let version = info["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            let build = info["CFBundleVersion"] as? String ?? "0"
            return (version, build)
        }

        if let parsed = parsedBundledInfoPlist() {
            return parsed
        }

        return ("0.0", "0")
    }()

    private static func parsedBundledInfoPlist() -> (shortVersion: String, build: String)? {
        guard let url = Bundle.module.url(forResource: "AppInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return nil
        }

        let build = plist["CFBundleVersion"] as? String ?? "0"
        return (version, build)
    }
}
