import Foundation
#if canImport(UsageBarRustCore)
import UsageBarRustCore
#endif

/// `git worktree remove [--force] <path>` run in `mainRepo`, through the one Rust implementation
/// `usagebar reap` also uses (rust/crates/core/src/git.rs). The standalone test harnesses compile this
/// file without the Rust core, so they take the runGit path; the CLI target always has it.
func worktreeRemoveGit(mainRepo: String, path: String, force: Bool) -> (out: String, err: String, code: Int32) {
#if canImport(UsageBarRustCore)
    let r = gitWorktreeRemove(mainRepo: mainRepo, path: path, force: force)
    return (r.out, r.err, r.code)
#else
    return runGit(force ? ["worktree", "remove", "--force", path] : ["worktree", "remove", path], cwd: mainRepo)
#endif
}
