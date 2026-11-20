import Foundation

// THE OTHER HALF OF THE SAME RELEASE: the skill's own folder.
//
// `/usagebar` was installed on every machine 0.44.0 reached and offered on none of them, because the
// skill sitting in `skills/usagebar` claims that name in the slash-command menu. The command file was
// perfect, the hook was registered, and the menu listed the skill under the name its frontmatter
// carries - so nothing about the install looked wrong from any surface the app has.
//
// What makes this its own fixture rather than a version check: the installs that need moving are
// ALREADY AT THE CURRENT VERSION. 0.44.0 wrote v16 into the folder that shadows the command, so the
// marker says "current" while the user has no command at all, and every mechanism this app has for
// travelling an edit is keyed on that marker. The move is keyed on the folder instead.
@MainActor
func runSkillFolderMoveChecks(tmp: URL) throws {
    let fm = FileManager.default
    func home(_ name: String, old: String? = nil, new: String? = nil) throws -> URL {
        let home = tmp.appendingPathComponent(name)
        for (file, text) in [(home.appendingPathComponent("skills/\(BrandPaths.cliName)/SKILL.md"), old),
                             (IntegrationsStore.claudeSkillFile(inHome: home), new)] {
            guard let text else { continue }
            try fm.createDirectory(at: file.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return home
    }
    let current = IntegrationsStore.skillMarkdown()
    let theirs = "---\nname: usagebar\ndescription: my own thing\n---\nmine"

    // A home as 0.44.0 left it: our skill, at the current version, in the folder that took the
    // command away.
    let moved = try home("moved-home", old: current)
    let movedOld = moved.appendingPathComponent("skills/\(BrandPaths.cliName)")
    let movedNow = IntegrationsStore.claudeSkillFile(inHome: moved)
    check("the skill's folder is not the slash command's name",
          movedNow.deletingLastPathComponent().lastPathComponent == IntegrationsStore.skillFolderName
              && IntegrationsStore.formerSkillFolderNames == [BrandPaths.cliName])
    let pass = IntegrationsStore.autoUpdateSkills(in: [movedNow])
    check("one pass moves an install that no version marker could have reached",
          pass.error == nil && pass.updated > 0 && pass.ours.map(\.path) == [movedNow.path])
    check("…the skill is at the folder Claude Code reads, with the text this build ships",
          (try? String(contentsOf: movedNow, encoding: .utf8)) == current)
    check("…and the old folder is gone entirely, not merely emptied",
          !fm.fileExists(atPath: movedOld.path))
    let second = IntegrationsStore.autoUpdateSkills(in: [movedNow])
    check("a second pass over a moved install changes nothing",
          second.updated == 0 && second.error == nil)

    // A SKILLS TREE SHARED BY TWO HOMES, which is the ordinary multi-account setup: one physical
    // folder, symlinked. The second spelling reaches a move that has already happened, so it must
    // find nothing to do rather than doing it twice or reporting a failure.
    let shared = try home("shared-home", old: current)
    let mirror = tmp.appendingPathComponent("mirror-home")
    try fm.createDirectory(at: mirror, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: mirror.appendingPathComponent("skills"),
                              withDestinationURL: shared.appendingPathComponent("skills"))
    let sharedPass = IntegrationsStore.autoUpdateSkills(
        in: [IntegrationsStore.claudeSkillFile(inHome: shared),
             IntegrationsStore.claudeSkillFile(inHome: mirror)])
    check("a shared skills tree is moved once and answers for both homes",
          sharedPass.error == nil && sharedPass.ours.count == 2
              && !fm.fileExists(atPath: shared.appendingPathComponent("skills/\(BrandPaths.cliName)").path))
    check("…and the second home reads the moved skill through its own spelling",
          (try? String(contentsOf: IntegrationsStore.claudeSkillFile(inHome: mirror),
                       encoding: .utf8)) == current)

    // A SKILL OF THE USER'S under the old name. We no longer install there, which makes that name
    // theirs: it is never moved, never deleted, and never read as an install of ours.
    let stranger = try home("stranger-home", old: theirs)
    let strangerPass = IntegrationsStore.autoUpdateSkills(
        in: [IntegrationsStore.claudeSkillFile(inHome: stranger)])
    check("a user's own skill in the old folder is left exactly where it is",
          strangerPass.updated == 0 && strangerPass.ours.isEmpty && strangerPass.error == nil
              && (try? String(contentsOf: stranger.appendingPathComponent("skills/\(BrandPaths.cliName)/SKILL.md"),
                              encoding: .utf8)) == theirs)
    check("…and nothing is installed beside it, because an absent skill stays absent",
          !fm.fileExists(atPath: IntegrationsStore.claudeSkillFile(inHome: stranger).path))

    // …while a file of theirs at the path we DO write to is the conflict the install has always
    // reported, named after the folder this app writes today.
    let occupied = try home("occupied-home", old: current, new: theirs)
    let blocked = IntegrationsStore.autoUpdateSkills(
        in: [IntegrationsStore.claudeSkillFile(inHome: occupied)])
    check("a stranger at the new path stops the move instead of clobbering them",
          blocked.error?.contains("skills/\(IntegrationsStore.skillFolderName)") == true
              && (try? String(contentsOf: IntegrationsStore.claudeSkillFile(inHome: occupied),
                              encoding: .utf8)) == theirs)
    check("…and our install keeps standing where it is until the move can happen",
          (try? String(contentsOf: occupied.appendingPathComponent("skills/\(BrandPaths.cliName)/SKILL.md"),
                       encoding: .utf8)) == current)

    // THE UNINSTALL reaches the old folder through the same call, which is what keeps a machine
    // that never got the move from keeping an orphan nothing is ever coming back for.
    let leftover = try home("leftover-home", old: current)
    check("clearing the former folders removes what is ours",
          try IntegrationsStore.clearFormerSkillFolders(
            besides: IntegrationsStore.claudeSkillFile(inHome: leftover))
              && !fm.fileExists(atPath: leftover.appendingPathComponent("skills/\(BrandPaths.cliName)").path))
    check("…and reports nothing to do when there is nothing of ours there",
          try !IntegrationsStore.clearFormerSkillFolders(
            besides: IntegrationsStore.claudeSkillFile(inHome: stranger)))

    // And the manifest, which on every machine that has been through 0.44.0 records the old path:
    // read as a home rather than as a file, so the uninstall and the move both reach the install
    // Claude Code actually loads.
    check("a path recorded before the move names the install of today",
          IntegrationsStore.currentSkillFile(
            forRecordedPath: moved.appendingPathComponent("skills/\(BrandPaths.cliName)/SKILL.md")).path
              == movedNow.path)
    check("…and a path already at the current folder is left as it is",
          IntegrationsStore.currentSkillFile(forRecordedPath: movedNow).path == movedNow.path)
}
