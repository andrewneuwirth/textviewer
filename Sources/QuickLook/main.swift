import Foundation

// App extensions have no main() of their own; PlugInKit's entry point takes
// over. SwiftPM can't express that, so the symbol is declared by hand.
@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

exit(NSExtensionMain())
