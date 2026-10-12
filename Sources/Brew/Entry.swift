#if SWIFT_PACKAGE
import BrewKit
#endif
import Darwin

@main
enum BrewApplication {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--report"),
           CommandLine.arguments.indices.contains(index + 1) {
            freopen(CommandLine.arguments[index + 1], "w", stdout)
            setbuf(stdout, nil)
        }
        runBrew()
    }
}
