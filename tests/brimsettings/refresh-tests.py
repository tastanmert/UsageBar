#!/usr/bin/env python3
"""Compile the production setting and timer bodies against an in-memory clock and defaults.
No UsageStore singleton, provider, credential store or network transport is linked.
"""
from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


settings = Path('UsageBar/Stores/SettingsStore.swift').read_text()
usage = Path('UsageBar/Stores/UsageStore.swift').read_text()
load = next(line.strip() for line in settings.splitlines()
            if 'refreshIntervalMinutes = [1, 2, 5, 15]' in line)
source = '''import Foundation
final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: Int] = [:]
    func set(_ value: Int, forKey key: String) { values[key] = value }
}
extension Double { static func now() -> Double { 1000 } }
final class FakeTimer {
    var cancelled = false
    var resumed = false
    var deadline: Double = 0
    var interval: Double = 0
    func cancel() { cancelled = true }
    func schedule(deadline: Double, repeating: Double) {
        self.deadline = deadline; interval = repeating
    }
    func setEventHandler(_ handler: @escaping () -> Void) {}
    func resume() { resumed = true }
}
enum DispatchSource {
    enum Queue { case main }
    static func makeTimerSource(queue: Queue) -> FakeTimer { FakeTimer() }
}
final class SettingsStore {
    static let shared = SettingsStore(1)
''' + block(settings, 'var refreshIntervalMinutes: Int {') + '''
    init(_ interval: Int) { ''' + load + ''' }
}
final class UsageStore {
    static let shared = UsageStore()
    var timer: FakeTimer?
    var mainTimerNextFire: Date?
    func refresh(userInitiated: Bool, trigger: Trigger) async { fatalError("unexpected transport") }
    enum Trigger { case timer }
''' + block(usage, 'func rescheduleRefresh() {') + '\n' + block(usage, 'private func scheduleTimer() {') + '''
}
func expect(_ value: Bool, _ message: String) {
    guard value else { fatalError(message) }
}
for invalid in [-1, 0, 3, 30, 60] {
    expect(SettingsStore(invalid).refreshIntervalMinutes == 1, "invalid interval fallback")
}
for minutes in [1, 2, 5, 15] {
    expect(SettingsStore(minutes).refreshIntervalMinutes == minutes, "valid saved selection")
    let old = UsageStore.shared.timer
    SettingsStore.shared.refreshIntervalMinutes = minutes
    expect(UserDefaults.standard.values["refreshIntervalMinutes"] == minutes, "selection persisted")
    let timer = UsageStore.shared.timer!
    expect(timer.interval == Double(minutes * 60), "real minutes, no hidden multiplier")
    expect(timer.deadline == 1000 + Double(minutes * 60), "new deadline on fake clock")
    expect(timer.resumed, "replacement timer started immediately")
    expect(old == nil || old!.cancelled, "previous timer cancelled")
}
print("PASS: refresh defaults, persistence and immediate timer replacement (fake clock, no transport)")
'''
with tempfile.TemporaryDirectory() as work:
    main = Path(work) / 'main.swift'
    main.write_text(source)
    binary = Path(work) / 'refresh-tests'
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
