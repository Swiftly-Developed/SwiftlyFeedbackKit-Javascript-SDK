import XCTVapor
@testable import SwiftlyFeedbackServer

final class AppTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        // Note: Tests require a PostgreSQL database running
        // Configure test database or skip integration tests
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
    }

    func testHealthCheck() async throws {
        try await configure(app)
        try await app.test(.GET, "health") { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }

    // Note: Full integration tests require PostgreSQL
    // Unit tests for models and validation can be added here
}
