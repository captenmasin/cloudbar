import Foundation

enum CloudBarResources {
    static var bundle: Bundle {
        if Bundle.main.url(forResource: "logo", withExtension: "svg") != nil {
            return Bundle.main
        }

        return Bundle.module
    }
}
