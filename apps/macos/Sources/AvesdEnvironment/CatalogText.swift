import Foundation

package struct CatalogText {
    private static let resources: Bundle = Bundle.main.bundleURL.pathExtension == "app" ? .main : .module
    package static let bundle: Bundle = resources === Bundle.main ? .main : bundle(for: Locale.preferredLanguages)

    package static func bundle(for languages: [String]) -> Bundle {
        let preferences = languages + [resources.developmentLocalization ?? "en"]
        let preferred = Bundle.preferredLocalizations(from: resources.localizations, forPreferences: preferences)
        guard let language = preferred.first, let url = resources.url(forResource: language, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return resources }
        return bundle
    }

    private let table: String
    private let key: StaticString
    private let arguments: String.LocalizationValue

    init(_ table: String, _ key: StaticString, _ arguments: String.LocalizationValue) {
        self.table = table
        self.key = key
        self.arguments = arguments
    }

    package func resource(in bundle: Bundle = Self.bundle, locale: Locale = .current) -> LocalizedStringResource {
        LocalizedStringResource(key, defaultValue: arguments, table: table, locale: locale, bundle: .atURL(bundle.bundleURL))
    }

    package var string: String { String(localized: resource()) }
}
