import Foundation
import ScreenSaver

@main
enum VerifySaverBundle {
    static func main() throws {
        guard let path = CommandLine.arguments.dropFirst().first,
              let bundle = Bundle(path: path) else {
            throw NSError(domain: "VerifySaverBundle", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Pass a .saver bundle path"])
        }
        guard bundle.load(),
              let principalClass = bundle.principalClass,
              principalClass is ScreenSaverView.Type else {
            throw NSError(domain: "VerifySaverBundle", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot load ScreenSaverView from bundle"])
        }
        print("Loaded \(bundle.bundleURL.lastPathComponent): \(NSStringFromClass(principalClass))")
    }
}
