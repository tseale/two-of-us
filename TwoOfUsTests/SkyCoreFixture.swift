import Foundation

/// The one reader of the numbers exported from the sky lab.
///
/// The `SkyCoreFixtures…` files beside this one are GENERATED (each by a
/// script in design/sky-lab/tools/swift-fixtures/, named in its header) and
/// hold nothing but the lab's answers as text — a table in a multi-line
/// string, never thousands of numeric literals, which the type checker
/// chokes on. How that text is read is here, written by hand, once, so a
/// change to the reading is one change and regenerating a fixture can never
/// alter it.
///
/// The text comes in two shapes:
/// - TABLES OF CELLS, comma-separated, one row a line, their columns named
///   in the table's doc comment (the sun, the night, the season, the colour,
///   the air, the palette and the camera's look): `rows` and `number`.
/// - TABLES OF WORDS, space-separated (the world, the camera, the moment,
///   the noise and his stars): `words` for plain lines, `records` for
///   "key value value …" lines, `Table` where the first line names the
///   columns; and `double(bits:)` / `float(bits:)` for the values the lab
///   gives as bit patterns, because they are compared to the bit.
enum SkyCoreFixture {
    // MARK: Tables of cells

    /// A comma-separated table's rows, each split into its cells (an empty
    /// cell is kept: it is a cell).
    static func rows(_ table: String) -> [[String]] {
        table.split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }

    /// A cell as the number the lab wrote. A cell that is not a number is a
    /// broken fixture, and reads as NaN so that every comparison with it
    /// fails.
    static func number(_ cell: String) -> Double {
        Double(cell) ?? .nan
    }

    // MARK: Tables of words

    /// The lines of a space-separated section, each as its words.
    static func words(_ text: String) -> [[String]] {
        text.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
    }

    /// "key value value …" lines → the values, by key.
    static func records(_ text: String) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for line in words(text) {
            guard let key = line.first else { continue }
            out[key] = Array(line.dropFirst())
        }
        return out
    }

    /// A space-separated table: the first line names the columns, every
    /// other line is a row.
    struct Table {
        let columns: [String]
        let rows: [[String]]

        init(_ text: String) {
            let lines = SkyCoreFixture.words(text)
            columns = lines.first ?? []
            rows = Array(lines.dropFirst())
        }

        /// The rows whose named columns hold exactly these words.
        func rows(where wanted: [String: String]) -> [[String]] {
            let picks = wanted.map { (columns.firstIndex(of: $0.key) ?? -1, $0.value) }
            return rows.filter { row in picks.allSatisfy { $0.0 >= 0 && row[$0.0] == $0.1 } }
        }

        /// A cell of the row, by its column's name; empty where the column
        /// is unknown.
        func text(_ row: [String], _ column: String) -> String {
            guard let index = columns.firstIndex(of: column), index < row.count else { return "" }
            return row[index]
        }

        /// A number of the row; NaN where the lab has none (`nil`) or the
        /// column is unknown.
        func number(_ row: [String], _ column: String) -> Double {
            SkyCoreFixture.number(text(row, column))
        }
    }

    // MARK: Bit patterns

    /// 16 hex digits → the double with those bits.
    static func double(bits text: String) -> Double {
        Double(bitPattern: UInt64(text, radix: 16) ?? 0x7ff8_0000_0000_0000)
    }

    /// 8 hex digits → the float with those bits, as the lab reads it back
    /// (a double); `inf` → infinity.
    static func float(bits text: String) -> Double {
        text == "inf" ? .infinity : Double(Float(bitPattern: UInt32(text, radix: 16) ?? 0x7fc0_0000))
    }
}
