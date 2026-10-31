import Foundation
import Testing
@testable import Cyclop

struct DisplayRefreshTests {
    @Test(arguments: [24, 30, 60, 120, 144])
    func frameRangeFollowsDisplay(_ fps: Int) {
        let range = FrameRefreshPolicy.range(maximumFPS: fps, constrained: false)
        #expect(range.maximum == Float(fps))
        #expect(range.preferred == Float(fps))
        #expect(range.minimum <= range.maximum)
        let limited = FrameRefreshPolicy.range(maximumFPS: fps, constrained: true)
        #expect(limited.maximum == Float(min(fps, 60)))
        #expect(limited.preferred == limited.maximum)
    }

    @Test func unavailableRefreshRateFallsBackToValidRange() {
        let range = FrameRefreshPolicy.range(maximumFPS: 0, constrained: false)
        #expect(range.minimum == 30)
        #expect(range.maximum == 60)
    }
}
