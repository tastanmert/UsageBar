import Foundation

// Render-path waste the panel and the menu bar used to pay on every redraw (field reports,
// field reports). Source text, because these are SwiftUI bodies and AppKit wiring
// this suite does not compile: each check names the shape the fix took, so the per-redraw call
// cannot come back unnoticed.

var failures = 0
func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL"): \(name)")
    if !condition { failures += 1 }
}
func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

let grid = source("UsageBar/Views/PopoverCardGrid.swift") + source("UsageBar/Views/PopoverDetailedLayout.swift")
let row = source("UsageBar/Views/AccountListRowView.swift") + source("UsageBar/Views/AccountListRowView+Controls.swift")
let fleet = source("UsageBar/Views/FleetStripView.swift")
let controller = source("UsageBar/MenuBar/StatusItemController.swift")
let button = source("UsageBar/MenuBar/StatusItemButton.swift")
let advisor = source("UsageBar/Views/AdvisorStripView.swift")
check("the sources this suite reads are readable",
      ![grid, row, fleet, controller, button, advisor].contains(where: \.isEmpty))

// a field report: the list asks the auto pick once per provider and hands each row its answer.
check("7Z the list computes the pick once per provider",
      grid.contains("compactMap { AccountFacts.autoPickID(providerID: $0) }")
          && grid.contains("isAutoPick: autoPicks.contains(usage.id)"))
check("7Z the row uses the answer it is handed", row.contains("isAutoPick ?? facts.isAutoPick"))

// a field report: the fleet callout's blocks are built on hover, not on every body.
check("82 no fleet target builds its blocks eagerly", !fleet.contains("usageBarTooltip(blocks: fleetTooltipBlocks"))
check("82 the fleet rows build them lazily",
      fleet.components(separatedBy: "usageBarTooltip(lazyBlocks: { fleetTooltipBlocks([summary]) }").count == 2)

// a field report: the advisor row's callout text is built on hover, not on every body.
check("23 the advisor tag builds its callout lazily",
      !advisor.contains(".usageBarTooltip(advisorTooltip(")
          && !advisor.contains(".usageBarTooltip(blocks: advisorTooltip(")
          && advisor.contains(".usageBarTooltip(lazyBlocks: { advisorTooltip(state) })"))

// a field report: the refresh job's tail queues the strip for the next run-loop turn.
check("37 the refresh hook queues the redraw",
      controller.contains("UsageStore.shared.onChange = { [weak self] in self?.updateButtonSoon() }"))
check("37 the queued redraw runs on the next turn, coalesced",
      button.contains("guard !Self.buttonUpdateQueued else { return }")
          && button.contains("DispatchQueue.main.async { [weak self] in"))

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
