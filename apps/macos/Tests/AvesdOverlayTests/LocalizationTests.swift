import AvesdEnvironment
import CAvesdCore
import Foundation
import Testing
@testable import AvesdOverlay

@Test func localizedCatalogsRenderNativeEventPresentations() throws {
    let options = AvesdOverlayOptions(seed: 1, hold_ms: 5000, width: 368, anchor_x: 65, reduced: true)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    func presentation(_ pointer: OpaquePointer?) throws -> OverlayPresentation {
        let session = try #require(pointer)
        defer { avesd_overlay_destroy(session) }
        return try decoder.decode(OverlayPresentation.self, from: Data(String(cString: avesd_overlay_content(session)).utf8))
    }
    let previews = try (UInt32(0)...5).map { try presentation(avesd_overlay_preview($0, options)) }
    func sunrise(minutes: Int) throws -> OverlayPresentation {
        let event = Data(#"{"id":"sun","kind":"sunrise","occurred_at":"2026-11-22T09:00:00Z","data":{"place":"Lisbon","time_zone":"Europe/Lisbon","minutes_later_than_yesterday":\#(minutes)}}"#.utf8)
        return try event.withUnsafeBytes { bytes in
            try presentation(avesd_overlay_create(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, options))
        }
    }

    for (language, menu, rain, spokenRain, sample, one, two) in [
        ("en", "Settings…", "Raining", "Rain in", "Sample event.", "1 minute later", "2 minutes earlier"),
        ("zh-Hans", "设置…", "正在下雨", "正在下雨", "这是示例事件。", "晚 1 分钟", "早 2 分钟"),
        ("es-419", "Configuración…", "Está lloviendo", "Está lloviendo", "Evento de ejemplo.", "1 minuto después", "2 minutos antes")
    ] {
        let bundle = CatalogText.bundle(for: [language])
        let locale = Locale(identifier: language)
        #expect(String(localized: SettingsText.menuSettings.resource(in: bundle, locale: locale)) == menu)
        let cacheCount = String(localized: SettingsText.cacheCount(2, "8 KB").resource(in: bundle, locale: locale))
        #expect(cacheCount.contains("2") && cacheCount.contains("8 KB"))
        let rendered = previews.map { $0.localized(in: bundle, locale: locale) }
        #expect(rendered.allSatisfy { !$0.headline.isEmpty && $0.accessibility.hasSuffix(sample) })
        #expect(rendered[0].caption == "UA 839")
        #expect(rendered[1].secondary == rain)
        #expect(rendered[1].accessibility.contains(spokenRain))
        let later = try sunrise(minutes: 1).localized(in: bundle, locale: locale)
        let earlier = try sunrise(minutes: -2).localized(in: bundle, locale: locale)
        #expect(!later.accessibility.contains(sample) && !earlier.accessibility.contains(sample))
        #expect(later.rows.last?.value.contains(one) == true)
        #expect(earlier.rows.last?.value.contains(two) == true)
        #expect(later.accessibility.contains(one) && earlier.accessibility.contains(two))
    }
}

@MainActor
@Test func migratedSourceUsesLocalizedNameUntilRenamed() async throws {
    try await withDefaults { defaults in
        let address = "https://example.test/legacy"
        defaults.set(address, forKey: "eventPollingURL")
        let preferences = DaemonPreferences(defaults: defaults)
        let source = try #require(preferences.sources.first)
        #expect(source.mode == .fixed && source.address == address && source.enabled)
        preferences.sources[0].address = "https://example.test/changed"
        let reloaded = DaemonPreferences(defaults: defaults)
        let migrated = try #require(reloaded.sources.first)
        let zh = CatalogText.bundle(for: ["zh-CN"])
        let es = CatalogText.bundle(for: ["es-MX"])
        #expect(migrated.id == source.id && migrated.name == nil)
        #expect(migrated.displayName(in: zh) == "自定义 Murmur")
        #expect(migrated.displayName(in: es) == "Murmur personalizado")

        reloaded.sources[0].name = "Custom Murmur"
        let named = try #require(DaemonPreferences(defaults: defaults).sources.first)
        #expect(named.displayName(in: zh) == "Custom Murmur")
    }
}
