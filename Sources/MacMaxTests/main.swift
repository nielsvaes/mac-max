let harness = Harness()

runAXGeometryTests(harness)
runClickPolicyTests(harness)
runFrameStoreTests(harness)
runAXIdentityTests(harness)

harness.finish()
