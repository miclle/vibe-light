import Foundation

enum AppResourceBundle {
    private static let resourceBundleName = "VibeLight_VibeLightApp.bundle"

    static var bundle: Bundle {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
           let bundle = Bundle(url: resourceURL) {
            return bundle
        }

        let adjacentURL = Bundle.main.bundleURL.appendingPathComponent(resourceBundleName)
        if let bundle = Bundle(url: adjacentURL) {
            return bundle
        }

        return Bundle.module
    }
}
