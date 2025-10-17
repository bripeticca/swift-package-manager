// This should build just fine, but we should receive a diagnostic warning.

func mySmallWarning() {
    let unusedVar = 42
    print("I am not using my var!")
}