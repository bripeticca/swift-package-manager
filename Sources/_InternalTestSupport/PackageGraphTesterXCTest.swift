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

import XCTest

import struct Basics.IdentifiableSet

import PackageModel
import PackageGraph

@available(*, deprecated, message: "Migrate to Swift Testing and use 'PackageGraphTester'")
public func PackageGraphTesterXCTest(_ graph: ModulesGraph, _ result: (PackageGraphResultXCTest) throws -> Void) rethrows {
    try result(PackageGraphResultXCTest(graph))
}

@available(*, deprecated, message: "Migrate to Swift Testing and use 'PackageGraphResult'")
public final class PackageGraphResultXCTest {
    public let graph: ModulesGraph

    public init(_ graph: ModulesGraph) {
        self.graph = graph
    }

    public func check(roots: PackageIdentity..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.rootPackages.map{$0.identity }.sorted(), roots.sorted(), file: file, line: line)
    }

    public func check(packages: PackageIdentity..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(graph.packages.map {$0.identity }.sorted(), packages.sorted(), file: file, line: line)
    }

    public func check(modules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            graph.allModules
                .filter { $0.type != .test }
                .map { $0.name }
                .sorted(), modules.sorted(), file: file, line: line)
    }

    public func check(products: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Set(graph.allProducts.map { $0.name }), Set(products), file: file, line: line)
    }

    public func check(reachableTargets: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Set(graph.reachableModules.map { $0.name }), Set(reachableTargets), file: file, line: line)
    }

    public func check(reachableProducts: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Set(graph.reachableProducts.map { $0.name }), Set(reachableProducts), file: file, line: line)
    }

    public func check(
        reachableBuildTargets: String...,
        in environment: BuildEnvironment,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let targets = Set(try self.reachableBuildTargets(in: environment).map({ $0.name }))
        XCTAssertEqual(targets, Set(reachableBuildTargets), file: file, line: line)
    }

    public func check(
        reachableBuildProducts: String...,
        in environment: BuildEnvironment,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let products = Set(try self.reachableBuildProducts(in: environment).map({ $0.name }))
        XCTAssertEqual(products, Set(reachableBuildProducts), file: file, line: line)
    }

    public func checkTarget(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedTargetResultXCTest) -> Void
    ) {
        let target = graph.module(for: name)

        guard let target else {
            return XCTFail("Target \(name) not found", file: file, line: line)
        }

        body(ResolvedTargetResultXCTest(target))
    }

    package func checkTargets(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        body: ([ResolvedTargetResultXCTest]) throws -> Void
    ) rethrows {
        try body(graph.allModules.filter { $0.name == name }.map(ResolvedTargetResultXCTest.init))
    }

    public func checkProduct(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedProductResultXCTest) -> Void
    ) {
        let product = graph.product(for: name)

        guard let product else {
            return XCTFail("Product \(name) not found", file: file, line: line)
        }

        body(ResolvedProductResultXCTest(product))
    }

    package func checkPackage(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedPackage) -> Void
    ) {
        guard let package = find(package: .init(stringLiteral: name)) else {
            return XCTFail("Product \(name) not found", file: file, line: line)
        }
        body(package)
    }

    public func check(testModules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            graph.allModules
                .filter{ $0.type == .test }
                .map{ $0.name }
                .sorted(), testModules.sorted(), file: file, line: line)
    }

    public func find(package: PackageIdentity) -> ResolvedPackage? {
        return graph.package(for: package)
    }

    private func reachableBuildTargets(in environment: BuildEnvironment) throws -> IdentifiableSet<ResolvedModule> {
        let inputTargets = graph.inputPackages.lazy.flatMap { $0.modules }
        let recursiveBuildTargetDependencies = try inputTargets
            .flatMap { try $0.recursiveDependencies(satisfying: environment) }
            .compactMap { $0.module }
        return IdentifiableSet(inputTargets).union(recursiveBuildTargetDependencies)
    }

    private func reachableBuildProducts(in environment: BuildEnvironment) throws -> IdentifiableSet<ResolvedProduct> {
        let recursiveBuildProductDependencies = try graph.inputPackages
            .lazy
            .flatMap { $0.modules }
            .flatMap { try $0.recursiveDependencies(satisfying: environment) }
            .compactMap { $0.product }
        return IdentifiableSet(graph.inputPackages.flatMap { $0.products }).union(recursiveBuildProductDependencies)
    }
}

@available(*, deprecated, message: "Migrate to Swift Testing and use 'ResolvedTargetResult'")
public final class ResolvedTargetResultXCTest {
    public let target: ResolvedModule

    init(_ target: ResolvedModule) {
        self.target = target
    }

    public func check(dependencies: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Set(dependencies), Set(target.dependencies.map({ $0.name })), file: file, line: line)
    }

    public func check(dependencies: [String], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Set(dependencies), Set(target.dependencies.map({ $0.name })), file: file, line: line)
    }

    public func checkDependency(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedTargetDependencyResultXCTest) -> Void
    ) {
        guard let dependency = target.dependencies.first(where: { $0.name == name }) else {
            return XCTFail("Dependency \(name) not found", file: file, line: line)
        }
        body(ResolvedTargetDependencyResultXCTest(dependency))
    }

    public func check(type: Module.Kind, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(type, target.type, file: file, line: line)
    }

    public func checkDeclaredPlatforms(_ platforms: [String: String], file: StaticString = #file, line: UInt = #line) {
        let targetPlatforms = Dictionary(
            uniqueKeysWithValues: target.supportedPlatforms.map { ($0.platform.name, $0.version.versionString) }
        )
        XCTAssertEqual(platforms, targetPlatforms, file: file, line: line)
    }

    public func checkDerivedPlatforms(_ platforms: [String: String], file: StaticString = #file, line: UInt = #line) {
        let derived = platforms.map {
            let platform = PlatformRegistry.default.platformByName[$0.key] ?? PackageModel.Platform
                .custom(name: $0.key, oldestSupportedVersion: $0.value)
            return self.target.getSupportedPlatform(for: platform, usingXCTest: self.target.type == .test)
        }
        let targetPlatforms = Dictionary(
            uniqueKeysWithValues: derived.map { ($0.platform.name, $0.version.versionString) }
        )
        XCTAssertEqual(platforms, targetPlatforms, file: file, line: line)
    }

    public func checkDerivedPlatformOptions(
        _ platform: PackageModel.Platform,
        options: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let platform = self.target.getSupportedPlatform(for: platform, usingXCTest: target.type == .test)
        XCTAssertEqual(platform.options, options, file: file, line: line)
    }

    package func checkBuildSetting(
        declaration: BuildSettings.Declaration,
        assignments: Set<BuildSettings.Assignment>?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            target.underlying.buildSettings.assignments[declaration].flatMap { Set($0) },
            assignments,
            file: file,
            line: line
        )
    }
}

@available(*, deprecated, message: "Migrate to Swift Testing and use 'ResolvedTargetDependencyResult'")
public final class ResolvedTargetDependencyResultXCTest {
    private let dependency: ResolvedModule.Dependency

    init(_ dependency: ResolvedModule.Dependency) {
        self.dependency = dependency
    }

    public func checkConditions(satisfy environment: BuildEnvironment, file: StaticString = #file, line: UInt = #line) {
        XCTAssert(dependency.conditions.allSatisfy({ $0.satisfies(environment) }), file: file, line: line)
    }

    public func checkConditions(
        dontSatisfy environment: BuildEnvironment,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssert(!dependency.conditions.allSatisfy({ $0.satisfies(environment) }), file: file, line: line)
    }

    public func checkTarget(
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedTargetResultXCTest) -> Void
    ) {
        guard case let .module(target, _) = self.dependency else {
            return XCTFail("Dependency \(dependency) is not a target", file: file, line: line)
        }
        body(ResolvedTargetResultXCTest(target))
    }

    public func checkProduct(
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedProductResultXCTest) -> Void
    ) {
        guard case let .product(product, _) = self.dependency else {
            return XCTFail("Dependency \(dependency) is not a product", file: file, line: line)
        }
        body(ResolvedProductResultXCTest(product))
    }
}

@available(*, deprecated, message: "Migrate to Swift Testing and use 'ResolvedProductResult'")
public final class ResolvedProductResultXCTest {
    private let product: ResolvedProduct

    init(_ product: ResolvedProduct) {
        self.product = product
    }

    public func check(modules: String..., file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Set(modules), Set(product.modules.map({ $0.name })), file: file, line: line)
    }

    public func check(type: ProductType, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(type, product.type, file: file, line: line)
    }

    public func checkDeclaredPlatforms(_ platforms: [String: String], file: StaticString = #file, line: UInt = #line) {
        let targetPlatforms = Dictionary(uniqueKeysWithValues: product.supportedPlatforms.map({ ($0.platform.name, $0.version.versionString) }))
        XCTAssertEqual(platforms, targetPlatforms, file: file, line: line)
    }

    public func checkDerivedPlatforms(_ platforms: [String: String], file: StaticString = #file, line: UInt = #line) {
        let derived = platforms.map {
            let platform = PlatformRegistry.default.platformByName[$0.key] ?? PackageModel.Platform.custom(name: $0.key, oldestSupportedVersion: $0.value)
            return product.getSupportedPlatform(for: platform, usingXCTest: product.isLinkingXCTest)
        }
        let targetPlatforms = Dictionary(uniqueKeysWithValues: derived.map({ ($0.platform.name, $0.version.versionString) }))
        XCTAssertEqual(platforms, targetPlatforms, file: file, line: line)
    }

    public func checkDerivedPlatformOptions(_ platform: PackageModel.Platform, options: [String], file: StaticString = #file, line: UInt = #line) {
        let platform = product.getSupportedPlatform(for: platform, usingXCTest: product.isLinkingXCTest)
        XCTAssertEqual(platform.options, options, file: file, line: line)
    }

    public func checkTarget(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        body: (ResolvedTargetResultXCTest) -> Void
    ) {
        guard let target = product.modules.first(where: { $0.name == name }) else {
            return XCTFail("Target \(name) not found", file: file, line: line)
        }
        body(ResolvedTargetResultXCTest(target))
    }
}
