//! Where the pieces of an installed UsageBar sit relative to each other.
use std::path::{Path, PathBuf};

/// The directory, next to the `usagebar` entry, that holds the Swift CLI it forwards to.
/// The Swift binary is named `usagebar` (BrandPaths.cliName) because the kernel names a process after
/// its file, and the supervisor registry, reload and worktree teardown recognise supervisors by that
/// name. Must match `swiftCLIDirectoryName` in UsageBarCLI/SupervisorRuntime.swift
/// (tests/run-entry-tests.sh compares the two).
pub const SWIFT_CLI_DIR: &str = "swift";
/// The Swift CLI's file name. Must match `BrandPaths.cliName` (UsageBar/Core/BrandPaths.swift).
pub const SWIFT_CLI_NAME: &str = "usagebar";

/// The Swift CLI for an entry binary at `entry` (already resolved through symlinks).
pub fn swift_cli(entry: &Path) -> Option<PathBuf> {
    Some(entry.parent()?.join(SWIFT_CLI_DIR).join(SWIFT_CLI_NAME))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sits_in_the_swift_directory_beside_the_entry() {
        let entry = Path::new("/Applications/UsageBar.app/Contents/Helpers/usagebar");
        assert_eq!(swift_cli(entry).unwrap(),
                   Path::new("/Applications/UsageBar.app/Contents/Helpers/swift/usagebar"));
    }
}
