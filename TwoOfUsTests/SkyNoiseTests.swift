import XCTest
@testable import TwoOfUs

/// The sky's hash and noise (`SkyNoise`) against the sky lab's own, BIT FOR
/// BIT: his stars are cast in order, each taking a place the earlier nights
/// left free, so a hash that differs in its last bit on one night moves every
/// star after it. The lab's values are in `SkyCoreFixturesStars` (exported by
/// `design/sky-lab/tools/swift-fixtures/stars.mjs` from `lab/nights.js`,
/// `lab/noise.js` and, on the lab's page, the sky module's own lattice
/// noise). Every comparison here is exact — no accuracy.
final class SkyNoiseTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesStars

    private func int(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let value = Int(text) else {
            XCTFail("not a whole number: \(text)", file: file, line: line)
            return 0
        }
        return value
    }

    private func number(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let value = Double(text) else {
            XCTFail("not a number: \(text)", file: file, line: line)
            return .nan
        }
        return value
    }

    /// A 0–1 hash from its 32 bits, as the lab makes it.
    private func unit(_ hex: String) -> Double {
        Double(UInt32(hex, radix: 16) ?? 0) / 4_294_967_296
    }

    // MARK: Hashes

    func testTheHashMatchesTheLab() {
        // Nights 1 – 200 under each of the salts a night is seeded with
        // (where it is cast, how bright, how warm, how it twinkles), the
        // salts of the leading page's sky, and numbers below nought.
        var checked = 0
        for row in SkyCoreFixture.words(Lab.hashes) where row.first == "run" {
            let salt = int(row[1]), from = int(row[2])
            for (i, hex) in row.dropFirst(3).enumerated() {
                XCTAssertEqual(SkyNoise.hash(from + i, salt: salt), unit(hex), "hash(\(from + i), \(salt))")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 9 * 200 + 10 * 60 + 80)
        XCTAssertEqual(SkyNoise.hash(7), SkyNoise.hash(7, salt: 0), "no salt is salt 0")
    }

    func testWholeNumbersWrapAsTheLabs() {
        // JavaScript's `| 0` keeps the low 32 bits of a whole number, and
        // the salt is added before it is cut: a night past 2³¹ or a salt
        // below nought gives the lab's hash, not a trap.
        var checked = 0
        for row in SkyCoreFixture.words(Lab.hashes) where row.first == "one" {
            XCTAssertEqual(SkyNoise.hash(int(row[1]), salt: int(row[2])), unit(row[3]), "hash(\(row[1]), \(row[2]))")
            checked += 1
        }
        XCTAssertEqual(checked, 12)
        for row in SkyCoreFixture.words(Lab.lattice) where row.first == "one" {
            XCTAssertEqual(SkyNoise.hash2(int(row[1]), int(row[2]), seed: int(row[3])), unit(row[4]),
                           "hash2(\(row[1]), \(row[2]), \(row[3]))")
            checked += 1
        }
        XCTAssertEqual(checked, 12 + 7)
    }

    func testEveryLatticePointIsTheLabs() {
        var checked = 0
        for row in SkyCoreFixture.words(Lab.lattice) where row.first == "run" {
            let seed = int(row[1]), y = int(row[2]), from = int(row[3])
            for (i, hex) in row.dropFirst(4).enumerated() {
                XCTAssertEqual(SkyNoise.hash2(from + i, y, seed: seed), unit(hex), "hash2(\(from + i), \(y), \(seed))")
                checked += 1
            }
        }
        // 32 across × 16 down, under three seeds (the sky's own lattice is seed 23)
        XCTAssertEqual(checked, 32 * 16 * 3)
    }

    func testASeededRunIsTheLabs() {
        // The tree is grown from one of these (seed 20260702): the same tree
        // on every phone.
        let rows = SkyCoreFixture.words(Lab.sequences)
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.contains { $0.first == "20260702" })
        for row in rows {
            var run = SkyNoise.Stream(seed: int(row[0]))
            XCTAssertEqual(row.count, 49)
            for (i, hex) in row.dropFirst().enumerated() {
                XCTAssertEqual(run.next(), unit(hex), "rng(\(row[0])), number \(i + 1)")
            }
        }
        var one = SkyNoise.Stream(), other = SkyNoise.Stream(seed: 1)
        XCTAssertEqual(one.next(), other.next(), "a run with no seed starts from 1")
    }

    // MARK: Noise

    func testSmoothNoiseIsTheLabs() {
        let rows = SkyCoreFixture.words(Lab.noise).filter { $0.first == "noise2" }
        XCTAssertEqual(rows.count, 172 + 4)
        for row in rows {
            let got = SkyNoise.noise(number(row[1]), number(row[2]), seed: int(row[3]))
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[4]).bitPattern, "noise2(\(row[1]), \(row[2]), \(row[3])) = \(got)")
        }
    }

    func testFractalNoiseIsTheLabs() {
        let rows = SkyCoreFixture.words(Lab.noise).filter { $0.first == "fbm2" }
        XCTAssertEqual(rows.count, 200)
        for row in rows {
            let got = SkyNoise.fractal(number(row[1]), number(row[2]), octaves: int(row[3]), gain: number(row[4]),
                                       lacunarity: number(row[5]), seed: int(row[6]))
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[7]).bitPattern, "fbm2(\(row.dropFirst().dropLast().joined(separator: ", "))) = \(got)")
        }
        // …and with nothing said, the lab's own five octaves
        let plain = rows.filter { Array($0[3...6]) == ["5", "0.5", "2", "0"] }
        XCTAssertGreaterThanOrEqual(plain.count, 100)
        for row in plain {
            XCTAssertEqual(SkyNoise.fractal(number(row[1]), number(row[2])).bitPattern, SkyCoreFixture.double(bits: row[7]).bitPattern)
        }

        let lines = SkyCoreFixture.words(Lab.noise).filter { $0.first == "fbm1" }
        XCTAssertEqual(lines.count, 60)
        for row in lines {
            let got = SkyNoise.fractal(along: number(row[1]), octaves: int(row[2]), gain: number(row[3]),
                                       lacunarity: number(row[4]), seed: int(row[5]))
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[6]).bitPattern, "fbm1(\(row[1]), …)")
        }
    }

    // MARK: The painted hill's own lattice

    func testTheHillsOwnNoiseIsTheLabs() {
        // On a lattice point, between two, below nought, past the lattice's
        // 256 (it repeats) — and a spread of 160 places.
        let values = SkyCoreFixture.words(Lab.drift).filter { $0.first == "vn" }
        XCTAssertEqual(values.count, 172 + 4)
        for row in values {
            let got = SkyNoise.value(number(row[1]), number(row[2]))
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[3]).bitPattern, "vn(\(row[1]), \(row[2])) = \(got)")
        }
        let octaves = SkyCoreFixture.words(Lab.drift).filter { $0.first == "fb" }
        XCTAssertEqual(octaves.count, 172 + 4)
        for row in octaves {
            let got = SkyNoise.drift(number(row[1]), number(row[2]), octaves: int(row[3]))
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[4]).bitPattern, "fb(\(row[1]), \(row[2]), \(row[3])) = \(got)")
        }
        XCTAssertEqual(SkyNoise.value(3.25, 7.5), SkyNoise.value(3.25 + 256, 7.5 - 512), "the lattice repeats every 256")
    }

    func testHisStarsDriftAsTheLabs() {
        // "The sky is gathered a little, slowly, into loose knots with open
        // sky between them": two samples of the hill's noise at a 150 pt
        // scale, as `starsFor` asks for them.
        let rows = SkyCoreFixture.words(Lab.drift).filter { $0.first == "knots" }
        XCTAssertEqual(rows.count, 80)
        for row in rows {
            let x = number(row[1]), y = number(row[2])
            XCTAssertEqual(SkyNoise.drift(x / 150 + 3.7, y / 150 + 1.3, octaves: 2).bitPattern, SkyCoreFixture.double(bits: row[3]).bitPattern)
            XCTAssertEqual(SkyNoise.drift(x / 150 + 9.1, y / 150 + 6.6, octaves: 2).bitPattern, SkyCoreFixture.double(bits: row[4]).bitPattern)
        }
    }

    func testNoiseFarOutIsStillTheLabsAndNeverATrap() {
        // Past 2⁶³ a whole number no longer fits an Int64, and a careless
        // conversion traps — in the middle of drawing Home. JavaScript's
        // `| 0` wraps there as anywhere, so the lab has an answer, and the
        // app has the same one. (No star is cast out there: this is the
        // promise that a wild number cannot bring the sky down.)
        let farOut = 9.2e18
        let smooth = SkyCoreFixture.words(Lab.noise).filter { $0.first == "noise2" && abs(number($0[1])) > farOut }
        XCTAssertEqual(smooth.count, 4)
        for row in smooth {
            XCTAssertEqual(SkyNoise.noise(number(row[1]), number(row[2]), seed: int(row[3])).bitPattern,
                           SkyCoreFixture.double(bits: row[4]).bitPattern, "noise2(\(row[1]), \(row[2]), \(row[3]))")
        }
        let hill = SkyCoreFixture.words(Lab.drift).filter { ($0.first == "vn" || $0.first == "fb") && abs(number($0[1])) > farOut }
        XCTAssertEqual(hill.count, 8)
        for row in hill {
            let got = row[0] == "vn" ? SkyNoise.value(number(row[1]), number(row[2]))
                : SkyNoise.drift(number(row[1]), number(row[2]), octaves: int(row[3]))
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[row.count - 1]).bitPattern, row.joined(separator: " "))
        }
        // …and what is no number at all gives no number, not a trap.
        XCTAssertTrue(SkyNoise.noise(.infinity, -.infinity).isNaN)
        XCTAssertTrue(SkyNoise.noise(.nan, 0.5, seed: 3).isNaN)
        XCTAssertTrue(SkyNoise.value(-.infinity, .nan).isNaN)
        XCTAssertTrue(SkyNoise.drift(.nan, .infinity).isNaN)
    }

    func testNoiseStaysBetweenNoughtAndOne() {
        for i in 0..<500 {
            let x = Double(i) * 0.731 - 180, y = Double(i) * -0.417 + 90
            for value in [SkyNoise.noise(x, y, seed: i), SkyNoise.fractal(x, y), SkyNoise.value(x, y), SkyNoise.drift(x, y),
                          SkyNoise.hash(i, salt: i % 9), SkyNoise.hash2(i, -i, seed: 23)] {
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThan(value, 1)
            }
        }
    }
}
