//! Transcript extraction shared by every Rust layer: reads one tick of a live transcript (scan.rs)
//! and one line off its bytes (line.rs). The C ABI over it lives in usagebar_ffi; the types here are
//! `repr(C)` because that crate hands them across it unchanged (rust/include/usagebar_core.h).

mod iso;
mod line;
pub mod scan;
pub mod tokenstats;
pub mod git;
pub mod reap;

pub use line::{read_line, UsageBarNeedles};

pub const ERR_PANIC: i32 = -1;
pub const ERR_ARGS: i32 = -2;
pub const ERR_NOFILE: i32 = -3;
pub const TS_NONE: i32 = 0;
pub const TS_PARSED: i32 = 1;
pub const TS_RAW: i32 = 2;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct UsageBarSpan {
    pub off: i64,
    pub len: i64,
}

impl UsageBarSpan {
    pub const ABSENT: UsageBarSpan = UsageBarSpan { off: 0, len: -1 };
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct UsageBarLineFields {
    pub present: u64,
    pub context_tokens: i64,
    pub ts_seconds: i64,
    pub ts_millis: i32,
    pub ts_kind: i32,
    pub utf8_valid: i32,
    pub reserved: i32,
    pub ts_raw: UsageBarSpan,
    pub uuid: UsageBarSpan,
    pub parent_uuid: UsageBarSpan,
    pub model: UsageBarSpan,
    pub excerpt: UsageBarSpan,
}

impl Default for UsageBarLineFields {
    fn default() -> Self {
        UsageBarLineFields {
            present: 0,
            context_tokens: -1,
            ts_seconds: 0,
            ts_millis: 0,
            ts_kind: TS_NONE,
            utf8_valid: 0,
            reserved: 0,
            ts_raw: UsageBarSpan::ABSENT,
            uuid: UsageBarSpan::ABSENT,
            parent_uuid: UsageBarSpan::ABSENT,
            model: UsageBarSpan::ABSENT,
            excerpt: UsageBarSpan::ABSENT,
        }
    }
}

/// One line of a scan: its fields (spans relative to the line), where it sits in the block's
/// bytes, and its `LINE_*` kind bits (scan.rs).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct UsageBarScanLine {
    pub fields: UsageBarLineFields,
    pub off: i64,
    pub len: i64,
    pub kind: u32,
    pub reserved: i32,
}

#[repr(C)]
#[derive(Debug)]
pub struct UsageBarScanBlock {
    pub start_offset: u64,
    pub new_offset: u64,
    pub end: u64,
    pub at_end: i32,
    pub truncated: i32,
    pub bytes: *mut u8,
    pub bytes_len: usize,
    pub lines: *mut UsageBarScanLine,
    pub line_count: usize,
    pub tail: UsageBarScanLine,
    pub has_tail: i32,
    pub reserved: i32,
}
