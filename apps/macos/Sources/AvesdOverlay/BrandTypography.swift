import CoreText
import SwiftUI

enum BrandTypography {
    static let wordmark = Font.custom("Futura-Medium", size: 17, relativeTo: .headline)
    static func code(_ size: CGFloat) -> Font { .custom("IBMPlexMono-Medium", fixedSize: size) }

    static func registerBundledFonts() {
        let resources: Bundle = Bundle.main.bundleURL.pathExtension == "app" ? .main : .module
        for url in resources.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [] {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
               let failure = error?.takeRetainedValue(),
               CFErrorGetCode(failure) != CTFontManagerError.alreadyRegistered.rawValue {
                NSLog("Could not load %@: %@", url.lastPathComponent, failure.localizedDescription)
            }
        }
    }
}
