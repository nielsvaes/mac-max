import Foundation

final class Harness {
    private var failures: [String] = []
    private var passes = 0
    private var currentTest = "<none>"

    func test(_ name: String, _ body: () -> Void) {
        currentTest = name
        body()
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                file: StaticString = #filePath, line: UInt = #line) {
        if condition {
            passes += 1
        } else {
            failures.append("\(currentTest): \(message())\n      at \(file):\(line)")
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                                   file: StaticString = #filePath, line: UInt = #line) {
        expect(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
    }

    func expectClose(_ actual: CGFloat, _ expected: CGFloat, accuracy: CGFloat = 0.0001,
                     file: StaticString = #filePath, line: UInt = #line) {
        expect(abs(actual - expected) <= accuracy,
               "expected \(expected) ± \(accuracy), got \(actual)", file: file, line: line)
    }

    func finish() -> Never {
        for failure in failures { print("FAIL  \(failure)") }
        print("\n\(passes) passed, \(failures.count) failed")
        exit(failures.isEmpty ? 0 : 1)
    }
}
