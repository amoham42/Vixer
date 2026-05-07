import XCTest
@testable import VolumeMixer

final class AppDiscoveryServiceTests: XCTestCase {
    func test_currentApps_excludesNonRegularActivationPolicy() {
        let service = AppDiscoveryService()
        service.refresh()
        // The Finder is always running and activationPolicy == .regular.
        let bundleIDs = service.apps.map(\.bundleID)
        XCTAssertTrue(bundleIDs.contains("com.apple.finder"),
                      "Finder should always be present in regular apps")
        // No agents (e.g. coreaudiod) should appear because they're not .regular.
        XCTAssertFalse(bundleIDs.contains(where: { $0.hasPrefix("com.apple.coreaudiod") }))
    }

    func test_apps_areSortedByLocalizedName() {
        let service = AppDiscoveryService()
        service.refresh()
        let names = service.apps.map(\.name)
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }
}
