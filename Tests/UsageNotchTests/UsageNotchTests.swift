import Foundation
import Testing
@testable import UsageNotch

@Test func remainingPercentageIsDerivedFromUsedPercentage() {
    let window = UsageWindow(usedPercent: 73)
    #expect(window.remainingPercent == 27)
}

@Test func remainingPercentageInputIsConvertedToUsedPercentage() {
    let window = UsageWindow.fromRemainingPercent(21, windowMinutes: 300)
    #expect(window.usedPercent == 79)
    #expect(window.windowMinutes == 300)
}

@Test func percentageIsClampedAtTheBoundary() {
    #expect(UsageWindow(usedPercent: -5).usedPercent == 0)
    #expect(UsageWindow(usedPercent: 105).usedPercent == 100)
}
