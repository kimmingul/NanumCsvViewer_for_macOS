import Foundation

public enum CsvRowParser {
    public static func parse(_ line: String, delimiter: Character, quote: Character = "\"") -> [String] {
        let scalars = Array(line.unicodeScalars)
        let delimiterScalar = delimiter.unicodeScalars.first!
        let quoteScalar = quote.unicodeScalars.first!
        let cr = UnicodeScalar(0x0D)!
        let lf = UnicodeScalar(0x0A)!
        var fields: [String] = []
        fields.reserveCapacity(16)
        var i = 0

        while true {
            if i < scalars.count, scalars[i] == quoteScalar {
                var field = String.UnicodeScalarView()
                i += 1
                while i < scalars.count {
                    let c = scalars[i]
                    if c == quoteScalar {
                        if i + 1 < scalars.count, scalars[i + 1] == quoteScalar {
                            field.append(quoteScalar)
                            i += 2
                        } else {
                            i += 1
                            break
                        }
                    } else if c == cr {
                        field.append(lf)
                        if i + 1 < scalars.count, scalars[i + 1] == lf {
                            i += 2
                        } else {
                            i += 1
                        }
                    } else {
                        field.append(c)
                        i += 1
                    }
                }
                while i < scalars.count, scalars[i] != delimiterScalar {
                    field.append(scalars[i])
                    i += 1
                }
                fields.append(String(field))
            } else {
                let start = i
                while i < scalars.count, scalars[i] != delimiterScalar {
                    i += 1
                }
                fields.append(String(String.UnicodeScalarView(scalars[start..<i])))
            }

            if i < scalars.count, scalars[i] == delimiterScalar {
                i += 1
                continue
            }
            break
        }

        return fields
    }
}
