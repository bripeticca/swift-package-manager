//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import SPMBuildCore
import Basics
import struct PackageModel.BuildEnvironment
import _InternalTestSupport
import Testing

struct BuildParametersTests {
    @Test
    func configurationDependentProperties() throws {
        var parameters = mockBuildParameters(
            destination: .host,
            environment: BuildEnvironment(platform: .linux, configuration: .debug)
        )
        #expect(parameters.enableTestability)
        parameters.configuration = .release
        #expect(!parameters.enableTestability)
    }
}
