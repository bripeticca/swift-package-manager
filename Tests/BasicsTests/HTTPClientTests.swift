//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@testable import Basics
import _Concurrency
import _InternalTestSupport
import Testing
import XCTest

class HTTPClientXCTest: XCTestCase {
    func testEponentialBackoff() async throws {
        try XCTSkipOnWindows(because: "https://github.com/swiftlang/swift-package-manager/issues/8501")
        let counter = SendableBox(0)
        let lastCall = SendableBox<Date>(Date())
        let maxAttempts = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let delay = SendableTimeInterval.milliseconds(100)

        let httpClient = HTTPClient { _, _ in
            let count = await counter.value
            let expectedDelta = pow(2.0, Double(count - 1)) * delay.timeInterval()!
            let delta = await Date().timeIntervalSince(lastCall.value)
            XCTAssertEqual(delta, expectedDelta, accuracy: 0.1)

            await counter.increment()
            await lastCall.resetDate()
            return .init(statusCode: errorCode)
        }
        var request = HTTPClient.Request(method: .get, url: "http://test")
        request.options.retryStrategy = .exponentialBackoff(maxAttempts: maxAttempts, baseDelay: delay)

        let response = try await httpClient.execute(request)
        XCTAssertEqual(response.statusCode, errorCode)
        let count = await counter.value
        XCTAssertEqual(count, maxAttempts, "retries should match")
    }
}


struct HTTPClientTests {
    @Test
    func head() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody: Data? = nil

        let httpClient = HTTPClient { request, _ in
            #expect(request.url == url)
            #expect(request.method == .head)
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            return .init(statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let response = try await httpClient.head(url, headers: requestHeaders)
        #expect(response.statusCode == responseStatus)
        self.expectResponseHeaders(response.headers, expected: responseHeaders)
        #expect(response.body == responseBody)
    }

    @Test
    func testGet() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = Data(UUID().uuidString.utf8)

        let httpClient = HTTPClient { request, _ in
            #expect(request.url == url)
            #expect(request.method == .get)
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            return .init(statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let response = try await httpClient.get(url, headers: requestHeaders)
        #expect(response.statusCode == responseStatus)
        self.expectResponseHeaders(response.headers, expected: responseHeaders)
        #expect(response.body == responseBody)
    }

    @Test
    func post() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestBody = Data(UUID().uuidString.utf8)
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = Data(UUID().uuidString.utf8)

        let httpClient = HTTPClient { request, _ in
            #expect(request.url == url)
            #expect(request.method == .post)
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            #expect(request.body == requestBody)
            return .init(statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let response = try await httpClient.post(url, body: requestBody, headers: requestHeaders)
        #expect(response.statusCode == responseStatus)
        self.expectResponseHeaders(response.headers, expected: responseHeaders)
        #expect(response.body == responseBody)
    }

    @Test
    func put() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestBody = Data(UUID().uuidString.utf8)
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = Data(UUID().uuidString.utf8)

        let httpClient = HTTPClient { request, _ in
            #expect(request.url == url)
            #expect(request.method == .put)
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            #expect(request.body == requestBody)
            return .init(statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let response = try await httpClient.put(url, body: requestBody, headers: requestHeaders)
        #expect(response.statusCode == responseStatus)
        self.expectResponseHeaders(response.headers, expected: responseHeaders)
        #expect(response.body == responseBody)
    }

    @Test
    func delete() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = Data(UUID().uuidString.utf8)

        let httpClient = HTTPClient { request, _ in
            #expect(request.url == url)
            #expect(request.method == .delete)
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            return .init(statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let response = try await httpClient.delete(url, headers: requestHeaders)
        #expect(response.statusCode == responseStatus)
        self.expectResponseHeaders(response.headers, expected: responseHeaders)
        #expect(response.body == responseBody)
    }

    @Test
    func extraHeaders() async throws {
        let url = URL("http://test")
        let globalHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let httpClient = HTTPClient(configuration: .init(requestHeaders: globalHeaders)) { request, _ in
            var expectedHeaders = globalHeaders
            expectedHeaders.merge(requestHeaders)
            self.expectRequestHeaders(request.headers, expected: expectedHeaders)
            return .init(statusCode: 200)
        }

        var request = HTTPClient.Request(method: .get, url: url, headers: requestHeaders)
        request.options.addUserAgent = true

        let response = try await httpClient.execute(request)
        #expect(response.statusCode == 200)
    }

    @Test
    func userAgent() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let httpClient = HTTPClient { request, _ in
            #expect(request.headers.contains("User-Agent"), "expecting User-Agent")
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            return .init(statusCode: 200)
        }
        var request = HTTPClient.Request(method: .get, url: url, headers: requestHeaders)
        request.options.addUserAgent = true

        let response = try await httpClient.execute(request)
        #expect(response.statusCode == 200)
    }

    @Test
    func noUserAgent() async throws {
        let url = URL("http://test")
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let httpClient = HTTPClient { request, _ in
            #expect(!request.headers.contains("User-Agent"), "expecting User-Agent")
            self.expectRequestHeaders(request.headers, expected: requestHeaders)
            return .init(statusCode: 200)
        }

        var request = HTTPClient.Request(method: .get, url: url, headers: requestHeaders)
        request.options.addUserAgent = false

        let response = try await httpClient.execute(request)
        #expect(response.statusCode == 200)
    }

    @Test
    func authorization() async throws {
        let url = URL("http://test")

        do {
            let authorization = UUID().uuidString

            let httpClient = HTTPClient { request, _ in
                #expect(request.headers.contains("Authorization"), "expecting Authorization")
                #expect(request.headers.get("Authorization").first == authorization)
                return .init(statusCode: 200)
            }

            var request = HTTPClient.Request(method: .get, url: url)
            request.options.authorizationProvider = { requestUrl in
                requestUrl == url ? authorization : nil
            }

            let response = try await httpClient.execute(request)
            #expect(response.statusCode == 200)
        }

        do {
            let httpClient = HTTPClient { request, _ in
                #expect(!request.headers.contains("Authorization"), "not expecting Authorization")
                return .init(statusCode: 200)
            }

            var request = HTTPClient.Request(method: .get, url: url)
            request.options.authorizationProvider = { _ in "" }

            let response = try await httpClient.execute(request)
            #expect(response.statusCode == 200)
        }
    }

    @Test
    func validResponseCodes() async throws {
        let statusCode = Int.random(in: 201 ..< 500)

        let httpClient = HTTPClient { _, _ in
            throw HTTPClientError.badResponseStatusCode(statusCode)
        }

        var request = HTTPClient.Request(method: .get, url: "http://test")
        request.options.validResponseCodes = [200]

        do {
            let response = try await httpClient.execute(request)
            Issue.record("unexpected success \(response)")
        } catch {
            #expect(error as? HTTPClientError == .badResponseStatusCode(statusCode))
        }
    }

    @Test
    func hostCircuitBreaker() async throws {
        let maxErrors = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let age = SendableTimeInterval.seconds(5)

        let host = "http://tes-\(UUID().uuidString).com"
        let configuration = HTTPClientConfiguration(circuitBreakerStrategy: .hostErrors(maxErrors: maxErrors, age: age))
        let httpClient = HTTPClient(configuration: configuration) { _, _ in
                .init(statusCode: errorCode)
        }

        // make the initial errors
        do {
            let counter = SendableBox(0)
            for index in (0 ..< maxErrors) {
                let response = try await httpClient.get(URL("\(host)/\(index)/foo"))
                await counter.increment()
                #expect(response.statusCode == errorCode)
            }
            let count = await counter.value
            #expect(count == maxErrors)
        }

        // these should all circuit break
        let counter = SendableBox(0)
        let total = Int.random(in: 10 ..< 20)
        for index in (0 ..< total) {
            do {
                let response = try await httpClient.get(URL("\(host)/\(index)/foo"))
                Issue.record("unexpected success \(response)")
            } catch {
                #expect(error as? HTTPClientError == .circuitBreakerTriggered)
            }

            await counter.increment()
        }

        let count = await counter.value
        #expect(count == total)
    }

    @Test
    func hostCircuitBreakerAging() async throws {
        let maxErrors = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let ageInMilliseconds = 100

        let host = "http://tes-\(UUID().uuidString).com"
        let configuration = HTTPClientConfiguration(
            circuitBreakerStrategy: .hostErrors(
                maxErrors: maxErrors,
                age: .milliseconds(ageInMilliseconds)
            )
        )
        let httpClient = HTTPClient(configuration: configuration) { request, _ in
            if request.url.lastPathComponent == "error" {
                return .init(statusCode: errorCode)
            } else if request.url.lastPathComponent == "okay" {
                return .okay()
            } else {
                throw StringError("unknown request \(request.url)")
            }
        }

        // make the initial errors
        do {
            let counter = SendableBox(0)
            for index in (0 ..< maxErrors) {
                let response = try await httpClient.get(URL("\(host)/\(index)/error"))
                await counter.increment()
                #expect(response.statusCode == errorCode)
            }
            let count = await counter.value
            #expect(count == maxErrors)
        }

        // these should not circuit break since they are deliberately aged
        let total = Int.random(in: 10 ..< 20)
        let count = ThreadSafeBox<Int>(0)

        for index in (0 ..< total) {
            // age it
            let sleepInterval = SendableTimeInterval.milliseconds(ageInMilliseconds)
            try await Task.sleep(nanoseconds: UInt64(sleepInterval.nanoseconds()!))
            let response = try await httpClient.get("\(host)/\(index)/okay")
            count.increment()
            #expect(response.statusCode == 200)
        }

        #expect(count.get() == total)
    }

    @Test
    func hTTPClientHeaders() async throws {
        var headers = HTTPClientHeaders()

        let items = (1 ... Int.random(in: 10 ... 20)).map { index in HTTPClientHeaders.Item(name: "header-\(index)", value: UUID().uuidString) }
        headers.add(items)

        #expect(headers.count == items.count)
        items.forEach { item in
            #expect(headers.get(item.name).first == item.value)
        }

        headers.add(items.first!)
        #expect(headers.count == items.count)

        let name = UUID().uuidString
        let values = (1 ... Int.random(in: 10 ... 20)).map { "value-\($0)" }
        values.forEach { value in
            headers.add(name: name, value: value)
        }
        #expect(headers.count == items.count + 1)
        #expect(values == headers.get(name))
    }

    @Test
    func exceedsDownloadSizeLimitProgress() async throws {
        let maxSize: Int64 = 50

        let httpClient = HTTPClient { request, progress in
            switch request.method {
                case .head:
                    return .init(
                        statusCode: 200,
                        headers: .init([.init(name: "Content-Length", value: "0")])
                    )
                case .get:
                    try progress?(Int64(maxSize * 2), 0)
                default:
                    Issue.record("method should match")
            }

            fatalError("unreachable")
        }

        var request = HTTPClient.Request(url: "http://test")
        request.options.maximumResponseSizeInBytes = 10

        do {
            let response = try await httpClient.execute(request)
            Issue.record("unexpected success \(response)")
        } catch {
            #expect(error as? HTTPClientError == .responseTooLarge(maxSize * 2))
        }
    }

    @Test
    func maxConcurrency() async throws {
        let maxConcurrentRequests = 2
        let concurrentRequests = SendableBox(0)

        var configuration = HTTPClient.Configuration()
        configuration.maxConcurrentRequests = maxConcurrentRequests
        let httpClient = HTTPClient(configuration: configuration) { request, _ in
            await concurrentRequests.increment()

            if await concurrentRequests.value > maxConcurrentRequests {
                Issue.record("too many concurrent requests \(concurrentRequests), expected \(maxConcurrentRequests)")
            }

            await concurrentRequests.decrement()

            return .okay()
        }

        let total = 1000
        try await withThrowingTaskGroup(of: HTTPClient.Response.self) { group in
            for _ in 0..<total {
                group.addTask {
                    try await httpClient.get("http://localhost/test")
                }
            }

            var results = [HTTPClient.Response]()
            for try await result in group {
                results.append(result)
            }

            #expect(results.count == total)

            for result in results {
                #expect(result.statusCode == 200)
            }
        }
    }

    private func expectRequestHeaders(_ headers: HTTPClientHeaders, expected: HTTPClientHeaders, sourceLocation: SourceLocation = #_sourceLocation) {
        let noAgent = HTTPClientHeaders(headers.filter { $0.name != "User-Agent" })
        #expect(noAgent == expected, sourceLocation: sourceLocation)
    }

    private func expectResponseHeaders(_ headers: HTTPClientHeaders, expected: HTTPClientHeaders, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(headers == expected, sourceLocation: sourceLocation)
    }

}
