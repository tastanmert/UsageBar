import Foundation

// A dev bundle even in the release test: DEBUG must still prevent writes there.
enum BuildVariant { static var isDev = true }
let body = Data(#"{"result":{"accessToken":"fake","refresh_token":"fake","nested":[{"SECRET":"fake","Authorization":"fake","cookies":["fake"],"credits":3}],"extraUsage":{"spent":1.5}}}"#.utf8)
let clean = try BrimUsageDiagnostics.redacted(body)
let root = try JSONSerialization.jsonObject(with: clean) as! [String: Any]
let result = root["result"] as! [String: Any]
assert(result["accessToken"] as? String == "[REDACTED]")
assert(result["refresh_token"] as? String == "[REDACTED]")
let nested = (result["nested"] as! [[String: Any]])[0]
for key in ["SECRET", "Authorization", "cookies"] { assert(nested[key] as? String == "[REDACTED]") }
assert(nested["credits"] as? Int == 3)
assert((result["extraUsage"] as? [String: Double])?["spent"] == 1.5)
do {
    _ = try BrimUsageDiagnostics.redacted(Data("invalid".utf8))
    fatalError("malformed JSON must fail closed")
} catch {}
#if DEBUG
assert(BrimUsageDiagnostics.enabled)
BuildVariant.isDev = false
assert(!BrimUsageDiagnostics.enabled)
BuildVariant.isDev = true
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: directory) }
try BrimUsageDiagnostics.write(body, name: "fixture.json", directory: directory)
let file = directory.appendingPathComponent("fixture.json")
let savedBody = try Data(contentsOf: file)
assert(savedBody == body)
for (url, mode) in [(directory, 0o700), (file, 0o600)] {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    assert((attributes[.posixPermissions] as? NSNumber)?.intValue == mode)
}
try BrimUsageDiagnostics.write(clean, name: "fixture.json", directory: directory)
let replacedBody = try Data(contentsOf: file)
assert(replacedBody == clean)
print("PASS: usage diagnostics DEBUG redaction, raw bytes, overwrite and 0700/0600 permissions")
#else
assert(!BrimUsageDiagnostics.enabled)
print("PASS: usage diagnostics release disabled even for dev bundle")
#endif
