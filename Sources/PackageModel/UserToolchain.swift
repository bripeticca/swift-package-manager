//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import TSCUtility
import enum TSCBasic.JSON

import class Basics.AsyncProcess

#if os(Windows)
private let hostExecutableSuffix = ".exe"
#else
private let hostExecutableSuffix = ""
#endif

// FIXME: This is messy and needs a redesign.
public final class UserToolchain: Toolchain {
    public typealias SwiftCompilers = (compile: AbsolutePath, manifest: AbsolutePath)

    /// The toolchain configuration.
    private let configuration: ToolchainConfiguration

    /// Path of the librarian.
    public let librarianPath: AbsolutePath

    /// Path of the `swiftc` compiler.
    public let swiftCompilerPath: AbsolutePath

    /// An array of paths to search for headers and modules at compile time.
    public let includeSearchPaths: [AbsolutePath]

    /// An array of paths to search for libraries at link time.
    public let librarySearchPaths: [AbsolutePath]

    /// An array of paths to use with binaries produced by this toolchain at run time.
    public let runtimeLibraryPaths: [AbsolutePath]

    /// Path containing Swift resources for dynamic linking.
    public var swiftResourcesPath: AbsolutePath? {
        swiftSDK.pathsConfiguration.swiftResourcesPath
    }

    /// Path containing Swift resources for static linking.
    public var swiftStaticResourcesPath: AbsolutePath? {
        swiftSDK.pathsConfiguration.swiftStaticResourcesPath
    }

    /// Additional flags to be passed to the build tools.
    public var extraFlags: BuildFlags

    /// Path of the `swift` interpreter.
    public var swiftInterpreterPath: AbsolutePath {
        self.swiftCompilerPath.parentDirectory.appending("swift" + hostExecutableSuffix)
    }

    private let fileSystem: any FileSystem

    /// The compilation destination object.
    @available(*, deprecated, renamed: "swiftSDK")
    public var destination: SwiftSDK { swiftSDK }

    /// The Swift SDK used by this toolchain.
    public let swiftSDK: SwiftSDK

    /// The target triple that should be used for compilation.
    @available(*, deprecated, renamed: "targetTriple")
    public var triple: Basics.Triple { targetTriple }

    public let targetTriple: Basics.Triple

    // A version string that can be used to identify the swift compiler version
    public let swiftCompilerVersion: String?

    /// The list of CPU architectures to build for.
    public let architectures: [String]?

    /// Search paths from the PATH environment variable.
    let envSearchPaths: [AbsolutePath]

    /// Only use search paths, do not fall back to `xcrun`.
    let useXcrun: Bool

    private var _clangCompiler: AbsolutePath?

    private let environment: Environment

    public let installedSwiftPMConfiguration: InstalledSwiftPMConfiguration

    /// Returns the runtime library for the given sanitizer.
    public func runtimeLibrary(for sanitizer: Sanitizer) throws -> AbsolutePath {
        // FIXME: This is only for SwiftPM development time support. It is OK
        // for now but we shouldn't need to resolve the symlink.  We need to lay
        // down symlinks to runtimes in our fake toolchain as part of the
        // bootstrap script.
        let swiftCompiler = try resolveSymlinks(self.swiftCompilerPath)

        let runtime = try swiftCompiler.appending(
            RelativePath(validating: "../../lib/swift/clang/lib/darwin/libclang_rt.\(sanitizer.shortName)_osx_dynamic.dylib")
        )

        // Ensure that the runtime is present.
        guard fileSystem.exists(runtime) else {
            throw InvalidToolchainDiagnostic("Missing runtime for \(sanitizer) sanitizer")
        }

        return runtime
    }

    // MARK: - private utilities

    private static func lookup(
        variable: String,
        searchPaths: [AbsolutePath],
        environment: Environment
    ) -> AbsolutePath? {
        lookupExecutablePath(filename: environment[.init(variable)], searchPaths: searchPaths)
    }

    private static func getTool(
        _ name: String,
        binDirectories: [AbsolutePath],
        fileSystem: any FileSystem
    ) throws -> AbsolutePath {
        let executableName = "\(name)\(hostExecutableSuffix)"
        var toolPath: AbsolutePath?

        for dir in binDirectories {
            let path = dir.appending(component: executableName)
            guard fileSystem.isExecutableFile(path) else {
                continue
            }
            toolPath = path
            // Take the first match.
            break
        }

        guard let toolPath else {
            throw InvalidToolchainDiagnostic("could not find CLI tool `\(name)` at any of these directories: \(binDirectories)")
        }
        return toolPath
    }

    private static func findTool(
        _ name: String,
        envSearchPaths: [AbsolutePath],
        useXcrun: Bool,
        fileSystem: any FileSystem
    ) throws -> AbsolutePath {
        if useXcrun {
            #if os(macOS)
            let foundPath = try AsyncProcess.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--find", name])
                .spm_chomp()
            return try AbsolutePath(validating: foundPath)
            #endif
        }

        return try getTool(name, binDirectories: envSearchPaths, fileSystem: fileSystem)
    }

    private static func getTargetInfo(swiftCompiler: AbsolutePath) throws -> JSON {
        // Call the compiler to get the target info JSON.
        let compilerOutput: String
        do {
            let result = try AsyncProcess.popen(args: swiftCompiler.pathString, "-print-target-info")
            compilerOutput = try result.utf8Output().spm_chomp()
        } catch {
            throw InternalError(
                "Failed to load target info (\(error.interpolationDescription))"
            )
        }
        // Parse the compiler's JSON output.
        do {
            return try JSON(string: compilerOutput)
        } catch {
            throw InternalError(
                "Failed to parse target info (\(error.interpolationDescription)).\nRaw compiler output: \(compilerOutput)"
            )
        }
    }

    private static func getHostTriple(targetInfo: JSON) throws -> Basics.Triple {
        // Get the triple string from the target info.
        let tripleString: String
        do {
            tripleString = try targetInfo.get("target").get("triple")
        } catch {
            throw InternalError(
                "Target info does not contain a triple string (\(error.interpolationDescription)).\nTarget info: \(targetInfo)"
            )
        }

        // Parse the triple string.
        do {
            return try Triple(tripleString)
        } catch {
            throw InternalError(
                "Failed to parse triple string (\(error.interpolationDescription)).\nTriple string: \(tripleString)"
            )
        }
    }

    private static func computeRuntimeLibraryPaths(targetInfo: JSON) throws -> [AbsolutePath] {
        var libraryPaths: [AbsolutePath] = []

        for runtimeLibPath in (try? (try? targetInfo.get("paths"))?.getArray("runtimeLibraryPaths")) ?? [] {
            guard case .string(let value) = runtimeLibPath else {
                continue
            }

            guard let path = try? AbsolutePath(validating: value) else {
                continue
            }

            libraryPaths.append(path)
        }

        return libraryPaths
    }

    private static func computeSwiftCompilerVersion(targetInfo: JSON) -> String? {
        // Use the new swiftCompilerTag if it's there
        if let swiftCompilerTag: String = targetInfo.get("swiftCompilerTag") {
            return swiftCompilerTag
        }

        // Default to the swift portion of the compilerVersion
        let compilerVersion: String
        do {
            compilerVersion = try targetInfo.get("compilerVersion")
        } catch {
            return nil
        }

        // Extract the swift version using regex from the description if available
        do {
            let regex = try Regex(#"\((swift(lang)?-[^ )]*)"#)
            if let match = try regex.firstMatch(in: compilerVersion), match.count > 1, let substring = match[1].substring {
                return String(substring)
            }

            let regex2 = try Regex(#"\(.*Swift (.*)[ )]"#)
            if let match2 = try regex2.firstMatch(in: compilerVersion), match2.count > 1, let substring = match2[1].substring {
                return "swift-\(substring)"
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: - public API

    public static func determineLibrarian(
        triple: Basics.Triple,
        binDirectories: [AbsolutePath],
        useXcrun: Bool,
        environment: Environment,
        searchPaths: [AbsolutePath],
        extraSwiftFlags: [String],
        fileSystem: any FileSystem
    ) throws -> AbsolutePath {
        let variable: String = triple.isApple() ? "LIBTOOL" : "AR"
        let tool: String = {
            if triple.isApple() { return "libtool" }
            if triple.isWindows() {
                if let librarian: AbsolutePath =
                    UserToolchain.lookup(
                        variable: "AR",
                        searchPaths: searchPaths,
                        environment: environment
                    )
                {
                    return librarian.basename
                }
                // TODO(5719) handle `-Xmanifest` vs `-Xswiftc`
                // `-use-ld=` is always joined in Swift.
                if let ld = extraSwiftFlags.first(where: { $0.starts(with: "-use-ld=") }) {
                    let linker = String(ld.split(separator: "=").last!)
                    return linker == "lld" ? "lld-link" : linker
                }
                return "link"
            }
            return "llvm-ar"
        }()

        if let librarian = UserToolchain.lookup(
            variable: variable,
            searchPaths: searchPaths,
            environment: environment
        ) {
            if fileSystem.isExecutableFile(librarian) {
                return librarian
            }
        }

        if let librarian = try? UserToolchain.getTool(tool, binDirectories: binDirectories, fileSystem: fileSystem) {
            return librarian
        }
        if triple.isApple() || triple.isWindows() {
            return try UserToolchain.findTool(tool, envSearchPaths: searchPaths, useXcrun: useXcrun, fileSystem: fileSystem)
        } else {
            if let librarian = try? UserToolchain.findTool(tool, envSearchPaths: searchPaths, useXcrun: false, fileSystem: fileSystem) {
                return librarian
            }
            // Fall back to looking for binutils `ar` if `llvm-ar` can't be found.
            if let librarian = try? UserToolchain.getTool("ar", binDirectories: binDirectories, fileSystem: fileSystem) {
                return librarian
            }
            return try UserToolchain.findTool("ar", envSearchPaths: searchPaths, useXcrun: false, fileSystem: fileSystem)
        }
    }

    /// Determines the Swift compiler paths for compilation and manifest parsing.
    public static func determineSwiftCompilers(
        binDirectories: [AbsolutePath],
        useXcrun: Bool,
        environment: Environment,
        searchPaths: [AbsolutePath],
        fileSystem: any FileSystem
    ) throws -> SwiftCompilers {
        func validateCompiler(at path: AbsolutePath?) throws {
            guard let path else { return }
            guard fileSystem.isExecutableFile(path) else {
                throw InvalidToolchainDiagnostic(
                    "could not find the `swiftc\(hostExecutableSuffix)` at expected path \(path)"
                )
            }
        }

        let lookup = { UserToolchain.lookup(variable: $0, searchPaths: searchPaths, environment: environment) }
        // Get overrides.
        let SWIFT_EXEC_MANIFEST = lookup("SWIFT_EXEC_MANIFEST")
        let SWIFT_EXEC = lookup("SWIFT_EXEC")

        // Validate the overrides.
        try validateCompiler(at: SWIFT_EXEC)
        try validateCompiler(at: SWIFT_EXEC_MANIFEST)

        // We require there is at least one valid swift compiler, either in the
        // bin dir or SWIFT_EXEC.
        let resolvedBinDirCompiler: AbsolutePath
        if let SWIFT_EXEC {
            resolvedBinDirCompiler = SWIFT_EXEC
        } else if let binDirCompiler = try? UserToolchain.getTool("swiftc", binDirectories: binDirectories, fileSystem: fileSystem) {
            resolvedBinDirCompiler = binDirCompiler
        } else {
            // Try to lookup swift compiler on the system which is possible when
            // we're built outside of the Swift toolchain.
            resolvedBinDirCompiler = try UserToolchain.findTool(
                "swiftc",
                envSearchPaths: searchPaths,
                useXcrun: useXcrun,
                fileSystem: fileSystem
            )
        }

        // The compiler for compilation tasks is SWIFT_EXEC or the bin dir compiler.
        // The compiler for manifest is either SWIFT_EXEC_MANIFEST or the bin dir compiler.
        return (compile: SWIFT_EXEC ?? resolvedBinDirCompiler, manifest: SWIFT_EXEC_MANIFEST ?? resolvedBinDirCompiler)
    }

    /// Returns the path to clang compiler tool.
    public func getClangCompiler() throws -> AbsolutePath {
        // Check if we already computed.
        if let clang = self._clangCompiler {
            return clang
        }

        // Check in the environment variable first.
        if let toolPath = UserToolchain.lookup(
            variable: "CC",
            searchPaths: self.envSearchPaths,
            environment: environment
        ) {
            self._clangCompiler = toolPath
            return toolPath
        }

        // Then, check the toolchain.
        if let toolPath = try? UserToolchain.getTool(
            "clang",
            binDirectories: self.swiftSDK.toolset.rootPaths,
            fileSystem: self.fileSystem
        ) {
            self._clangCompiler = toolPath
            return toolPath
        }

        // Otherwise, lookup it up on the system.
        let toolPath = try UserToolchain.findTool(
            "clang",
            envSearchPaths: self.envSearchPaths,
            useXcrun: useXcrun,
            fileSystem: self.fileSystem
        )
        self._clangCompiler = toolPath
        return toolPath
    }

    public func _isClangCompilerVendorApple() throws -> Bool? {
        // Assume the vendor is Apple on macOS.
        // FIXME: This might not be the best way to determine this.
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// Returns the path to lldb.
    public func getLLDB() throws -> AbsolutePath {
        // Look for LLDB next to the compiler first.
        if let lldbPath = try? UserToolchain.getTool(
            "lldb",
            binDirectories: [self.swiftCompilerPath.parentDirectory],
            fileSystem: self.fileSystem
        ) {
            return lldbPath
        }
        // If that fails, fall back to xcrun, PATH, etc.
        return try UserToolchain.findTool(
            "lldb",
            envSearchPaths: self.envSearchPaths,
            useXcrun: useXcrun,
            fileSystem: self.fileSystem
        )
    }

    /// Returns the path to llvm-cov tool.
    public func getLLVMCov() throws -> AbsolutePath {
        try UserToolchain.getTool(
            "llvm-cov",
            binDirectories: [self.swiftCompilerPath.parentDirectory],
            fileSystem: self.fileSystem
        )
    }

    /// Returns the path to llvm-prof tool.
    public func getLLVMProf() throws -> AbsolutePath {
        try UserToolchain.getTool(
            "llvm-profdata",
            binDirectories: [self.swiftCompilerPath.parentDirectory],
            fileSystem: self.fileSystem
        )
    }

    /// Returns the path to llvm-objdump tool.
    package func getLLVMObjdump() throws -> AbsolutePath {
        try UserToolchain.getTool(
            "llvm-objdump",
            binDirectories: [self.swiftCompilerPath.parentDirectory],
            fileSystem: self.fileSystem
        )
    }

    public func getSwiftAPIDigester() throws -> AbsolutePath {
        if let envValue = UserToolchain.lookup(
            variable: "SWIFT_API_DIGESTER",
            searchPaths: self.envSearchPaths,
            environment: environment
        ) {
            return envValue
        }
        return try UserToolchain.getTool(
            "swift-api-digester",
            binDirectories: [self.swiftCompilerPath.parentDirectory],
            fileSystem: self.fileSystem

        )
    }

    public func getSymbolGraphExtract() throws -> AbsolutePath {
        if let envValue = UserToolchain.lookup(
            variable: "SWIFT_SYMBOLGRAPH_EXTRACT",
            searchPaths: self.envSearchPaths,
            environment: environment
        ) {
            return envValue
        }
        return try UserToolchain.getTool(
            "swift-symbolgraph-extract",
            binDirectories: [self.swiftCompilerPath.parentDirectory],
            fileSystem: self.fileSystem
        )
    }

#if os(macOS)
    public func getSwiftTestingHelper() throws -> AbsolutePath {
        // The helper would be located in `.build/<config>` directory when
        // SwiftPM is built locally and `usr/libexec/swift/pm` directory in
        // an installed version.
        let binDirectories = self.swiftSDK.toolset.rootPaths +
            self.swiftSDK.toolset.rootPaths.map {
                $0.parentDirectory.appending(components: ["libexec", "swift", "pm"])
            }

        return try UserToolchain.getTool(
            "swiftpm-testing-helper",
            binDirectories: binDirectories,
            fileSystem: self.fileSystem
        )
    }
#endif

    internal static func deriveSwiftCFlags(
        triple: Basics.Triple,
        swiftSDK: SwiftSDK,
        environment: Environment,
        fileSystem: any FileSystem
    ) throws -> [String] {
        var swiftCompilerFlags = swiftSDK.toolset.knownTools[.swiftCompiler]?.extraCLIOptions ?? []

        if let linker = swiftSDK.toolset.knownTools[.linker]?.path {
            swiftCompilerFlags += ["-ld-path=\(linker)"]
        }

        guard let sdkDir = swiftSDK.pathsConfiguration.sdkRootPath else {
            if triple.isWindows() {
                // Windows uses a variable named SDKROOT to determine the root of
                // the SDK.  This is not the same value as the SDKROOT parameter
                // in Xcode, however, the value represents a similar concept.
                if let sdkroot = environment.windowsSDKRoot {
                    var runtime: [String] = []
                    var xctest: [String] = []
                    var swiftTesting: [String] = []
                    var extraSwiftCFlags: [String] = []

                    if let settings = WindowsSDKSettings(
                        reading: sdkroot.appending("SDKSettings.plist"),
                        observabilityScope: nil,
                        filesystem: fileSystem
                    ) {
                        switch settings.defaults.runtime {
                        case .multithreadedDebugDLL:
                            runtime = ["-libc", "MDd"]
                        case .multithreadedDLL:
                            runtime = ["-libc", "MD"]
                        case .multithreadedDebug:
                            runtime = ["-libc", "MTd"]
                        case .multithreaded:
                            runtime = ["-libc", "MT"]
                        }
                    }

                    // The layout of the SDK is as follows:
                    //
                    // Library/Developer/Platforms/[PLATFORM].platform/Developer/Library/<Project>-[VERSION]/...
                    // Library/Developer/Platforms/[PLATFORM].platform/Developer/SDKs/[PLATFORM].sdk/...
                    //
                    // SDKROOT points to [PLATFORM].sdk
                    let platform = sdkroot.parentDirectory.parentDirectory.parentDirectory

                    if let info = WindowsPlatformInfo(
                        reading: platform.appending("Info.plist"),
                        observabilityScope: nil,
                        filesystem: fileSystem
                    ) {
                        let XCTestInstallation: AbsolutePath =
                            platform.appending("Developer")
                                .appending("Library")
                                .appending("XCTest-\(info.defaults.xctestVersion)")

                        xctest = try [
                            "-I",
                            AbsolutePath(
                                validating: "usr/lib/swift/windows",
                                relativeTo: XCTestInstallation
                            ).pathString,
                            // Migration Path
                            //
                            // Older Swift (<=5.7) installations placed the
                            // XCTest Swift module into the architecture
                            // specified directory.  This was in order to match
                            // the SDK setup.  However, the toolchain finally
                            // gained the ability to consult the architecture
                            // independent directory for Swift modules, allowing
                            // the merged swiftmodules.  XCTest followed suit.
                            "-I",
                            AbsolutePath(
                                validating: "usr/lib/swift/windows/\(triple.archName)",
                                relativeTo: XCTestInstallation
                            ).pathString,
                            "-L",
                            AbsolutePath(
                                validating: "usr/lib/swift/windows/\(triple.archName)",
                                relativeTo: XCTestInstallation
                            ).pathString,
                        ]

                        // Migration Path
                        //
                        // In order to support multiple parallel installations
                        // of an SDK, we need to ensure that we can have all the
                        // architecture variant libraries available.  Prior to
                        // this getting enabled (~5.7), we always had a singular
                        // installed SDK.  Prefer the new variant which has an
                        // architecture subdirectory in `bin` if available.
                        let implib = try AbsolutePath(
                            validating: "usr/lib/swift/windows/XCTest.lib",
                            relativeTo: XCTestInstallation
                        )
                        if fileSystem.exists(implib) {
                            xctest.append(contentsOf: ["-L", implib.parentDirectory.pathString])
                        }

                        if let swiftTestingVersion = info.defaults.swiftTestingVersion {
                            let swiftTestingInstallation: AbsolutePath =
                                platform.appending("Developer")
                                    .appending("Library")
                                    .appending("Testing-\(swiftTestingVersion)")

                            swiftTesting = try [
                                "-I",
                                AbsolutePath(
                                    validating: "usr/lib/swift/windows",
                                    relativeTo: swiftTestingInstallation
                                ).pathString,
                                "-L",
                                AbsolutePath(
                                    validating: "usr/lib/swift/windows/\(triple.archName)",
                                    relativeTo: swiftTestingInstallation
                                ).pathString
                            ]
                        }

                        extraSwiftCFlags = info.defaults.extraSwiftCFlags ?? []
                    }

                    return ["-sdk", sdkroot.pathString] + runtime + xctest + swiftTesting + extraSwiftCFlags
                }
            }

            return swiftCompilerFlags
        }

        return (
            triple.isDarwin() || triple.isAndroid() || triple.isWASI() || triple.isWindows()
                ? ["-sdk", sdkDir.pathString]
                : []
        ) + swiftCompilerFlags
    }

    // MARK: - initializer

    public enum SearchStrategy {
        case `default`
        case custom(searchPaths: [AbsolutePath], useXcrun: Bool = true)
    }

    @available(*, deprecated, message: "use init(swiftSDK:environment:searchStrategy:customLibrariesLocation) instead")
    public convenience init(
        destination: SwiftSDK,
        environment: Environment = .current,
        searchStrategy: SearchStrategy = .default,
        customLibrariesLocation: ToolchainConfiguration.SwiftPMLibrariesLocation? = nil
    ) throws {
        try self.init(
            swiftSDK: destination,
            environment: environment,
            searchStrategy: searchStrategy,
            customLibrariesLocation: customLibrariesLocation,
            fileSystem: localFileSystem
        )
    }

    public init(
        swiftSDK: SwiftSDK,
        environment: Environment = .current,
        searchStrategy: SearchStrategy = .default,
        customTargetInfo: JSON? = nil,
        customLibrariesLocation: ToolchainConfiguration.SwiftPMLibrariesLocation? = nil,
        customInstalledSwiftPMConfiguration: InstalledSwiftPMConfiguration? = nil,
        fileSystem: any FileSystem = localFileSystem
    ) throws {
        self.swiftSDK = swiftSDK
        self.environment = environment

        switch searchStrategy {
        case .default:
            // Get the search paths from PATH.
            self.envSearchPaths = getEnvSearchPaths(
                pathString: environment[.path],
                currentWorkingDirectory: fileSystem.currentWorkingDirectory
            )
            self.useXcrun = !(fileSystem is InMemoryFileSystem)
        case .custom(let searchPaths, let useXcrun):
            self.envSearchPaths = searchPaths
            self.useXcrun = useXcrun
        }

        let swiftCompilers = try UserToolchain.determineSwiftCompilers(
            binDirectories: swiftSDK.toolset.rootPaths,
            useXcrun: self.useXcrun,
            environment: environment,
            searchPaths: self.envSearchPaths,
            fileSystem: fileSystem
        )
        self.swiftCompilerPath = swiftCompilers.compile
        self.architectures = swiftSDK.architectures

        if let customInstalledSwiftPMConfiguration {
            self.installedSwiftPMConfiguration = customInstalledSwiftPMConfiguration
        } else {
            let path = swiftCompilerPath.parentDirectory.parentDirectory.appending(components: [
                "share", "pm", "config.json",
            ])
            self.installedSwiftPMConfiguration = try Self.loadJSONResource(
                config: path,
                type: InstalledSwiftPMConfiguration.self,
                default: InstalledSwiftPMConfiguration.default)
        }

        // targetInfo from the compiler
        let targetInfo = try customTargetInfo ?? Self.getTargetInfo(swiftCompiler: swiftCompilers.compile)

        // Get compiler version information from target info
        self.swiftCompilerVersion = Self.computeSwiftCompilerVersion(targetInfo: targetInfo)

        // Get the list of runtime libraries from the target info
        self.runtimeLibraryPaths = try Self.computeRuntimeLibraryPaths(targetInfo: targetInfo)

        // Use the triple from Swift SDK or compute the host triple from the target info
        var triple = try swiftSDK.targetTriple ?? Self.getHostTriple(targetInfo: targetInfo)

        // Change the triple to the specified arch if there's exactly one of them.
        // The Triple property is only looked at by the native build system currently.
        if let architectures = self.architectures, architectures.count == 1 {
            let components = triple.tripleString.drop(while: { $0 != "-" })
            triple = try Triple(architectures[0] + components)
        }

        self.targetTriple = triple

        var swiftCompilerFlags: [String] = []
        var extraLinkerFlags: [String] = []

        let swiftTestingPath: AbsolutePath? = try Self.deriveSwiftTestingPath(
            derivedSwiftCompiler: swiftCompilers.compile,
            swiftSDK: self.swiftSDK,
            triple: triple,
            environment: environment,
            fileSystem: fileSystem
        )

        if triple.isMacOSX, let swiftTestingPath {
            // Swift Testing is a framework (e.g. from CommandLineTools) so use -F.
            if swiftTestingPath.extension == "framework" {
                swiftCompilerFlags += ["-F", swiftTestingPath.pathString]

            // Otherwise Swift Testing is assumed to be a swiftmodule + library, so use -I and -L.
            } else {
                swiftCompilerFlags += [
                    "-I", swiftTestingPath.pathString,
                    "-L", swiftTestingPath.pathString,
                ]
            }
        }

        // Specify the plugin path for Swift Testing's macro plugin if such a
        // path exists in this toolchain.
        if let swiftTestingPluginPath = Self.deriveSwiftTestingPluginPath(
            derivedSwiftCompiler: swiftCompilers.compile,
            fileSystem: fileSystem
        ) {
            swiftCompilerFlags += ["-plugin-path", swiftTestingPluginPath.pathString]
        }

        swiftCompilerFlags += try Self.deriveSwiftCFlags(
            triple: triple,
            swiftSDK: swiftSDK,
            environment: environment,
            fileSystem: fileSystem
        )

        extraLinkerFlags += swiftSDK.toolset.knownTools[.linker]?.extraCLIOptions ?? []

        self.extraFlags = BuildFlags(
            cCompilerFlags: swiftSDK.toolset.knownTools[.cCompiler]?.extraCLIOptions ?? [],
            cxxCompilerFlags: swiftSDK.toolset.knownTools[.cxxCompiler]?.extraCLIOptions ?? [],
            swiftCompilerFlags: swiftCompilerFlags,
            linkerFlags: extraLinkerFlags,
            xcbuildFlags: swiftSDK.toolset.knownTools[.xcbuild]?.extraCLIOptions ?? [])

        self.includeSearchPaths = swiftSDK.pathsConfiguration.includeSearchPaths ?? []
        self.librarySearchPaths = swiftSDK.pathsConfiguration.includeSearchPaths ?? []

        self.librarianPath = try swiftSDK.toolset.knownTools[.librarian]?.path ?? UserToolchain.determineLibrarian(
            triple: triple,
            binDirectories: swiftSDK.toolset.rootPaths,
            useXcrun: useXcrun,
            environment: environment,
            searchPaths: envSearchPaths,
            extraSwiftFlags: self.extraFlags.swiftCompilerFlags,
            fileSystem: fileSystem
        )

        if let sdkDir = swiftSDK.pathsConfiguration.sdkRootPath {
            let sysrootFlags = [triple.isDarwin() ? "-isysroot" : "--sysroot", sdkDir.pathString]
            self.extraFlags.cCompilerFlags.insert(contentsOf: sysrootFlags, at: 0)
        }

        if triple.isWindows() {
            if let root = environment.windowsSDKRoot {
                if let settings = WindowsSDKSettings(
                    reading: root.appending("SDKSettings.plist"),
                    observabilityScope: nil,
                    filesystem: fileSystem
                ) {
                    switch settings.defaults.runtime {
                    case .multithreadedDebugDLL:
                        // Defines _DEBUG, _MT, and _DLL
                        // Linker uses MSVCRTD.lib
                        self.extraFlags.cCompilerFlags += [
                            "-D_DEBUG",
                            "-D_MT",
                            "-D_DLL",
                            "-Xclang",
                            "--dependent-lib=msvcrtd",
                        ]

                    case .multithreadedDLL:
                        // Defines _MT, and _DLL
                        // Linker uses MSVCRT.lib
                        self.extraFlags.cCompilerFlags += ["-D_MT", "-D_DLL", "-Xclang", "--dependent-lib=msvcrt"]

                    case .multithreadedDebug:
                        // Defines _DEBUG, and _MT
                        // Linker uses LIBCMTD.lib
                        self.extraFlags.cCompilerFlags += ["-D_DEBUG", "-D_MT", "-Xclang", "--dependent-lib=libcmtd"]

                    case .multithreaded:
                        // Defines _MT
                        // Linker uses LIBCMT.lib
                        self.extraFlags.cCompilerFlags += ["-D_MT", "-Xclang", "--dependent-lib=libcmt"]
                    }
                }
            }
        }

        let swiftPMLibrariesLocation = try customLibrariesLocation ?? Self.deriveSwiftPMLibrariesLocation(
            swiftCompilerPath: swiftCompilerPath,
            swiftSDK: swiftSDK,
            environment: environment,
            fileSystem: fileSystem
        )

        let xctestPath: AbsolutePath?
        if case .custom(_, let useXcrun) = searchStrategy, !useXcrun {
            xctestPath = nil
        } else {
            xctestPath = try Self.deriveXCTestPath(
                swiftSDK: self.swiftSDK,
                triple: triple,
                environment: environment,
                fileSystem: fileSystem
            )
        }

        self.configuration = .init(
            librarianPath: librarianPath,
            swiftCompilerPath: swiftCompilers.manifest,
            swiftCompilerFlags: self.extraFlags.swiftCompilerFlags,
            swiftCompilerEnvironment: environment,
            swiftPMLibrariesLocation: swiftPMLibrariesLocation,
            sdkRootPath: self.swiftSDK.pathsConfiguration.sdkRootPath,
            xctestPath: xctestPath,
            swiftTestingPath: swiftTestingPath
        )

        self.fileSystem = fileSystem
    }

    private static func deriveSwiftPMLibrariesLocation(
        swiftCompilerPath: AbsolutePath,
        swiftSDK: SwiftSDK,
        environment: Environment,
        fileSystem: any FileSystem
    ) throws -> ToolchainConfiguration.SwiftPMLibrariesLocation? {
        // Look for an override in the env.
        if let pathEnvVariable = environment["SWIFTPM_CUSTOM_LIBS_DIR"] ?? environment["SWIFTPM_PD_LIBS"] {
            if environment["SWIFTPM_PD_LIBS"] != nil {
                print("SWIFTPM_PD_LIBS was deprecated in favor of SWIFTPM_CUSTOM_LIBS_DIR")
            }
            // We pick the first path which exists in an environment variable
            // delimited by the platform specific string separator.
            #if os(Windows)
            let separator: Character = ";"
            #else
            let separator: Character = ":"
            #endif
            let paths = pathEnvVariable.split(separator: separator).map(String.init)
            for pathString in paths {
                if let path = try? AbsolutePath(validating: pathString), fileSystem.exists(path) {
                    // we found the custom one
                    return .init(root: path)
                }
            }

            // fail if custom one specified but not found
            throw InternalError(
                "Couldn't find the custom libraries location defined by SWIFTPM_CUSTOM_LIBS_DIR / SWIFTPM_PD_LIBS: \(pathEnvVariable)"
            )
        }

        // FIXME: the following logic is pretty fragile, but has always been this way
        // an alternative cloud be to force explicit locations to always be set explicitly when running in Xcode/SwiftPM
        // debug and assert if not set but we detect that we are in this mode

        for applicationPath in swiftSDK.toolset.rootPaths {
            // this is the normal case when using the toolchain
            let librariesPath = applicationPath.parentDirectory.appending(components: "lib", "swift", "pm")
            if fileSystem.exists(librariesPath) {
                return .init(root: librariesPath)
            }

            // this tests if we are debugging / testing SwiftPM with Xcode
            let manifestFrameworksPath = applicationPath.appending(
                components: "PackageFrameworks",
                "PackageDescription.framework"
            )
            let pluginFrameworksPath = applicationPath.appending(components: "PackageFrameworks", "PackagePlugin.framework")
            if fileSystem.exists(manifestFrameworksPath), fileSystem.exists(pluginFrameworksPath) {
                return .init(
                    manifestLibraryPath: manifestFrameworksPath,
                    pluginLibraryPath: pluginFrameworksPath
                )
            }

            // this tests if we are debugging / testing SwiftPM with SwiftPM
            if localFileSystem.exists(applicationPath.appending("swift-package")) {
                // Newer versions of SwiftPM will emit modules to a "Modules" subdirectory, but we're also staying compatible with older versions for development.
                let modulesPath: AbsolutePath
                if localFileSystem.exists(applicationPath.appending("Modules")) {
                    modulesPath = applicationPath.appending("Modules")
                } else {
                    modulesPath = applicationPath
                }

                return .init(
                    manifestLibraryPath: applicationPath,
                    manifestModulesPath: modulesPath,
                    pluginLibraryPath: applicationPath,
                    pluginModulesPath: modulesPath
                )
            }
        }

        // we are using a SwiftPM outside a toolchain, use the compiler path to compute the location
        return .init(swiftCompilerPath: swiftCompilerPath)
    }

    private static func derivePluginServerPath(triple: Basics.Triple) throws -> AbsolutePath? {
        if triple.isDarwin() {
            let pluginServerPathFindArgs = ["/usr/bin/xcrun", "--find", "swift-plugin-server"]
            if let path = try? AsyncProcess.checkNonZeroExit(arguments: pluginServerPathFindArgs, environment: [:])
                .spm_chomp() {
                return try AbsolutePath(validating: path)
            }
        }
        return .none
    }

    private static func getWindowsPlatformInfo(
        swiftSDK: SwiftSDK,
        environment: Environment,
        fileSystem: any FileSystem
    ) -> (AbsolutePath, WindowsPlatformInfo)? {
        let sdkRoot: AbsolutePath? = if let sdkDir = swiftSDK.pathsConfiguration.sdkRootPath {
            sdkDir
        } else if let sdkDir = environment.windowsSDKRoot {
            sdkDir
        } else {
            nil
        }

        guard let sdkRoot else {
            return nil
        }

        // The layout of the SDK is as follows:
        //
        // Library/Developer/Platforms/[PLATFORM].platform/Developer/Library/<Project>-[VERSION]/...
        // Library/Developer/Platforms/[PLATFORM].platform/Developer/SDKs/[PLATFORM].sdk/...
        //
        // SDKROOT points to [PLATFORM].sdk
        let platform = sdkRoot.parentDirectory.parentDirectory.parentDirectory

        guard let info = WindowsPlatformInfo(
            reading: platform.appending("Info.plist"),
            observabilityScope: nil,
            filesystem: fileSystem
        ) else {
            return nil
        }

        return (platform, info)
    }

    // TODO: We should have some general utility to find tools.
    private static func deriveXCTestPath(
        swiftSDK: SwiftSDK,
        triple: Basics.Triple,
        environment: Environment,
        fileSystem: any FileSystem
    ) throws -> AbsolutePath? {
        if triple.isDarwin() {
            // XCTest is optional on macOS, for example when Xcode is not installed
            let xctestFindArgs = ["/usr/bin/xcrun", "--sdk", "macosx", "--find", "xctest"]
            if let path = try? AsyncProcess.checkNonZeroExit(arguments: xctestFindArgs, environment: environment)
                .spm_chomp()
            {
                return try AbsolutePath(validating: path)
            }
        } else if triple.isWindows() {
            if let (platform, info) = getWindowsPlatformInfo(
                swiftSDK: swiftSDK,
                environment: environment,
                fileSystem: fileSystem
            ) {
                let xctest: AbsolutePath =
                    platform.appending("Developer")
                        .appending("Library")
                        .appending("XCTest-\(info.defaults.xctestVersion)")

                // Migration Path
                //
                // In order to support multiple parallel installations of an
                // SDK, we need to ensure that we can have all the architecture
                // variant libraries available.  Prior to this getting enabled
                // (~5.7), we always had a singular installed SDK.  Prefer the
                // new variant which has an architecture subdirectory in `bin`
                // if available.
                switch triple.arch {
                case .x86_64: // amd64 x86_64 x86_64h
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin64")
                    if fileSystem.exists(path) {
                        return path
                    }

                case .x86: // i386 i486 i586 i686 i786 i886 i986
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin32")
                    if fileSystem.exists(path) {
                        return path
                    }

                case .arm: // armv7 and many more
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin32a")
                    if fileSystem.exists(path) {
                        return path
                    }

                case .aarch64: // aarch6 arm64
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin64a")
                    if fileSystem.exists(path) {
                        return path
                    }

                default:
                    // Fallback to the old-style layout.  We should really
                    // report an error in this case - this architecture is
                    // unavailable.
                    break
                }

                // Assume that we are in the old-style layout.
                return xctest.appending("usr")
                    .appending("bin")
            }
        }
        return nil
    }

    /// Find the swift-testing path if it is within a path that will need extra search paths.
    private static func deriveSwiftTestingPath(
        derivedSwiftCompiler: Basics.AbsolutePath,
        swiftSDK: SwiftSDK,
        triple: Basics.Triple,
        environment: Environment,
        fileSystem: any FileSystem
    ) throws -> AbsolutePath? {
        if triple.isDarwin() {
            // If this is CommandLineTools all we need to add is a frameworks path.
            if let frameworksPath = try? AbsolutePath(
                validating: "../../Library/Developer/Frameworks",
                relativeTo: resolveSymlinks(derivedSwiftCompiler).parentDirectory
            ), fileSystem.exists(frameworksPath.appending("Testing.framework")) {
                return frameworksPath
            }

            guard let toolchainLibDir = try? toolchainLibDir(swiftCompilerPath: derivedSwiftCompiler) else {
                return nil
            }

            let testingLibDir = toolchainLibDir.appending(components: ["swift", "macosx", "testing"])
            if fileSystem.exists(testingLibDir) {
                return testingLibDir
            }
        } else if triple.isWindows() {
            guard let (platform, info) = getWindowsPlatformInfo(
                swiftSDK: swiftSDK,
                environment: environment,
                fileSystem: fileSystem
            ) else {
                return nil
            }

            guard let swiftTestingVersion = info.defaults.swiftTestingVersion else {
                return nil
            }

            let swiftTesting: AbsolutePath =
                platform.appending("Developer")
                    .appending("Library")
                    .appending("Testing-\(swiftTestingVersion)")

            let binPath: AbsolutePath? = switch triple.arch {
            case .x86_64: // amd64 x86_64 x86_64h
                swiftTesting.appending("usr")
                    .appending("bin64")
            case .x86: // i386 i486 i586 i686 i786 i886 i986
                swiftTesting.appending("usr")
                    .appending("bin32")
            case .arm: // armv7 and many more
                swiftTesting.appending("usr")
                    .appending("bin32a")
            case .aarch64: // aarch6 arm64
                swiftTesting.appending("usr")
                    .appending("bin64a")
            default:
                nil
            }

            if let path = binPath, fileSystem.exists(path) {
                return path
            }
        }

        return nil
    }

    /// Derive the plugin path needed to locate the Swift Testing macro plugin,
    /// if such a path exists in the toolchain of the specified compiler.
    ///
    /// - Parameters:
    ///   - derivedSwiftCompiler: The derived path of the Swift compiler to use
    ///       when deriving the Swift Testing plugin path.
    ///   - fileSystem: The file system instance to use when validating the path
    ///       to return.
    ///
    /// - Returns: A path to the directory containing Swift Testing's macro
    ///     plugin, or `nil` if the path does not exist or cannot be determined.
    ///
    /// The path returned is a directory containing a library, suitable for
    /// passing to a client compiler via the `-plugin-path` flag.
    private static func deriveSwiftTestingPluginPath(
        derivedSwiftCompiler: Basics.AbsolutePath,
        fileSystem: any FileSystem
    ) -> AbsolutePath? {
        guard let toolchainLibDir = try? toolchainLibDir(swiftCompilerPath: derivedSwiftCompiler) else {
            return nil
        }

        if let pluginsPath = try? AbsolutePath(validating: "swift/host/plugins/testing", relativeTo: toolchainLibDir), fileSystem.exists(pluginsPath) {
            return pluginsPath
        }

        return nil
    }

    public var sdkRootPath: AbsolutePath? {
        configuration.sdkRootPath
    }

    public var swiftCompilerEnvironment: Environment {
        configuration.swiftCompilerEnvironment
    }

    public var swiftCompilerFlags: [String] {
        configuration.swiftCompilerFlags
    }

    public var swiftCompilerPathForManifests: AbsolutePath {
        configuration.swiftCompilerPath
    }

    public var swiftPMLibrariesLocation: ToolchainConfiguration.SwiftPMLibrariesLocation {
        configuration.swiftPMLibrariesLocation
    }

    public var xctestPath: AbsolutePath? {
        configuration.xctestPath
    }

    public var swiftTestingPath: AbsolutePath? {
        configuration.swiftTestingPath
    }

    private static func loadJSONResource<T: Decodable>(
        config: AbsolutePath, type: T.Type, `default`: T
    )
        throws -> T
    {
        if localFileSystem.exists(config) {
            return try JSONDecoder.makeWithDefaults().decode(
                path: config,
                fileSystem: localFileSystem,
                as: type)
        }

        return `default`
    }
}

extension Environment {
    fileprivate var windowsSDKRoot: AbsolutePath? {
        if let SDKROOT = self["SDKROOT"], let sdkDir = try? AbsolutePath(validating: SDKROOT) {
            return sdkDir
        }
        return nil
    }
}
