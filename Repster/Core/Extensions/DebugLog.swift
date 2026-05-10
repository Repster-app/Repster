import Foundation

@inlinable
func dbg(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
