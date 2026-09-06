import Foundation
import Testing
@testable import Nootch

// A settable clock, so the TTL and backoff behaviour can be checked without
// waiting minutes for real time to pass.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSince1970: 1_000_000)

    var date: Date {
        lock.lock()
        defer { lock.unlock() }
        return now
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        now += interval
    }
}

private struct Loader {
    let clock = TestClock()
    private let box = Box()

    final class Box: @unchecked Sendable {
        let lock = NSLock()
        var reads = 0
        var result: TokenLookup = .found("first")
    }

    var reads: Int { box.lock.withLock { box.reads } }
    func setResult(_ result: TokenLookup) { box.lock.withLock { box.result = result } }

    func load() -> TokenLookup {
        box.lock.withLock {
            box.reads += 1
            return box.result
        }
    }
}

@Test func cachedTokenIsReusedWithinTTL() {
    let loader = Loader()
    let cache = TokenCache(now: { loader.clock.date })

    #expect(cache.value(loader: loader.load) == "first")
    loader.clock.advance(TokenCache.foundTTL - 1)
    #expect(cache.value(loader: loader.load) == "first")
    // One read, not one per refresh: this is what keeps the password dialog
    // from appearing every 30 seconds.
    #expect(loader.reads == 1)

    loader.clock.advance(2)
    loader.setResult(.found("second"))
    #expect(cache.value(loader: loader.load) == "second")
    #expect(loader.reads == 2)
}

// A missing credential is cheap to re-read and raises no prompt, so it must
// expire quickly — otherwise `claude login` would not be noticed for minutes.
@Test func absentTokenExpiresSoonerThanADeniedOne() {
    #expect(TokenCache.absentTTL < TokenCache.foundTTL)
    #expect(TokenCache.deniedTTL > TokenCache.foundTTL)

    let loader = Loader()
    loader.setResult(.absent)
    let cache = TokenCache(now: { loader.clock.date })

    #expect(cache.value(loader: loader.load) == nil)
    loader.clock.advance(TokenCache.absentTTL + 1)
    loader.setResult(.found("after-login"))
    #expect(cache.value(loader: loader.load) == "after-login")
}

// A refused Keychain must not be retried straight away; each retry is another
// password dialog.
@Test func deniedTokenIsNotRetriedImmediately() {
    let loader = Loader()
    loader.setResult(.denied)
    let cache = TokenCache(now: { loader.clock.date })

    #expect(cache.value(loader: loader.load) == nil)
    loader.clock.advance(TokenCache.absentTTL + 1)
    #expect(cache.value(loader: loader.load) == nil)
    #expect(loader.reads == 1)
}

// Regression: invalidate() used to re-arm the floor on every rejection. With
// the 30s refresh loop rejecting continuously, the floor was pushed out before
// it could ever lapse, so the Keychain was never read again and a re-login went
// unnoticed until restart.
@Test func repeatedRejectionsStillAllowAReadOnceTheFloorLapses() {
    let loader = Loader()
    let cache = TokenCache(now: { loader.clock.date })
    #expect(cache.value(loader: loader.load) == "first")

    // Simulate the refresh loop: every 30s the stale token is served and
    // rejected again, for longer than the floor.
    loader.setResult(.found("renewed"))
    var elapsed: TimeInterval = 0
    while elapsed < TokenCache.reloadFloor {
        cache.invalidate()
        loader.clock.advance(30)
        elapsed += 30
        _ = cache.value(loader: loader.load)
    }

    // Once the floor has genuinely lapsed the cache must read again and pick up
    // the token the user just refreshed.
    #expect(cache.value(loader: loader.load) == "renewed")
    #expect(loader.reads == 2)
}

// The floor exists so that a token the API keeps refusing does not become a
// password dialog every cycle.
@Test func rejectionHoldsOffTheNextReadUntilTheFloorLapses() {
    let loader = Loader()
    let cache = TokenCache(now: { loader.clock.date })
    #expect(cache.value(loader: loader.load) == "first")

    cache.invalidate()
    loader.clock.advance(30)
    // Still inside the floor: no new read, and the stale token keeps being
    // served so the "login expired" error stays in place.
    #expect(cache.value(loader: loader.load) == "first")
    #expect(loader.reads == 1)
}
