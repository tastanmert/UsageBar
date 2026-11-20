import Foundation
// No binary resolution or environment inspection in these transport fixtures.
enum CLIRunner { static func resolve(_ name: String) -> String? { nil } }
struct CLISearchPath {
    static let shared = CLISearchPath()
    func environment(for executable: String) -> [String: String] { [:] }
}
