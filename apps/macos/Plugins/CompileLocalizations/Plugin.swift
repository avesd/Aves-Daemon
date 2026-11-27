import Foundation
import PackagePlugin

@main
struct CompileLocalizations: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let package = context.package.directoryURL
        let output = context.pluginWorkDirectoryURL
        let script = package.appending(path: "compile-localizations.ts")
        let tables = ["Settings", "Overlay", "InfoPlist"]
        let languages = ["en", "zh-Hans", "es-419"]
        let catalogs = tables.map { package.appending(path: "Localization/\($0).xcstrings") }
        let products = languages.flatMap { language in
            tables.map { table in
                let ext = table == "InfoPlist" ? "strings" : "stringsdict"
                return output.appending(path: "\(language).lproj/\(table).\(ext)")
            }
        }
        return [.buildCommand(
            displayName: "Validate and compile Aves Daemon translations",
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["node", script.path, output.path, languages.joined(separator: ",")] + catalogs.map(\.path),
            inputFiles: [script, package.appending(path: "Info.plist")] + catalogs,
            outputFiles: [output.appending(path: "CatalogSymbols.swift")] + products
        )]
    }
}
