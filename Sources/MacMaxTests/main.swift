let harness = Harness()

harness.test("harness reports a passing expectation") {
    harness.expectEqual(1 + 1, 2)
}

harness.finish()
