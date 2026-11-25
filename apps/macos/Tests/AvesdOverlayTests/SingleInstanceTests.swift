import AvesdEnvironment
import Foundation
import Testing
@testable import AvesdOverlay

@Test func eachChannelHoldsItsOwnLockUntilExit() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var locks: [InstanceLock] = []
    for channel in ChannelProfile.all.values {
        let file = directory.appending(path: channel.bundleIdentifier)
        locks.append(try #require(try InstanceLock(at: file)))
        #expect(try InstanceLock(at: file) == nil)
    }
    locks.removeAll()
    let local = try #require(ChannelProfile.all["local"])
    #expect(try InstanceLock(at: directory.appending(path: local.bundleIdentifier)) != nil)
}
