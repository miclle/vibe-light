import Foundation

enum AppResourceBundle {
    private static let resourceBundleName = "VibeLight_VibeLightApp.bundle"

    static var bundle: Bundle {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName),
            Bundle.module.bundleURL,
        ]

        for candidate in candidates {
            guard let candidate, let bundle = Bundle(url: candidate) else {
                continue
            }
            return bundle
        }

        return Bundle.module
    }
}
