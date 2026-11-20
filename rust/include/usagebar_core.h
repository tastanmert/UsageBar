#ifndef USAGEBAR_CORE_H
#define USAGEBAR_CORE_H
#include <stddef.h>
#include <stdint.h>

// C ABI of rust/ (usagebar_core). Mirrored field for field by rust/crates/ffi/src/lib.rs; the ctxrust
// suite asserts both sides agree on every size and offset.

#define USAGEBAR_ERR_PANIC (-1)
#define USAGEBAR_ERR_ARGS (-2)
#define USAGEBAR_ERR_NOFILE (-3)

#define USAGEBAR_TS_NONE 0
#define USAGEBAR_TS_PARSED 1
#define USAGEBAR_TS_RAW 2

/// A value inside the line: byte offset and length. len < 0 means absent.
typedef struct {
    int64_t off;
    int64_t len;
} UsageBarSpan;

typedef struct {
    uint64_t present;        /* bit i set: needle i occurs in the line */
    int64_t context_tokens;  /* -1: no reading (contextTokens(inLine:) == nil) */
    int64_t ts_seconds;      /* USAGEBAR_TS_PARSED: whole seconds since 1970, UTC */
    int32_t ts_millis;       /* USAGEBAR_TS_PARSED: 0...999 */
    int32_t ts_kind;         /* USAGEBAR_TS_* */
    int32_t utf8_valid;      /* 1 valid, 0 not (the line is then skipped, as it always was) */
    int32_t reserved;
    UsageBarSpan ts_raw;        /* the stamp text, set for PARSED and RAW */
    UsageBarSpan uuid, parent_uuid, model, excerpt;
} UsageBarLineFields;

typedef struct UsageBarNeedles UsageBarNeedles;

/// Builds one SIMD finder per needle. NULL when count > 64, a needle is empty, or on panic.
UsageBarNeedles *usagebar_needles_new(const uint8_t *const *ptrs, const size_t *lens, size_t count);
/// Reads one line (no trailing newline). 0 ok, USAGEBAR_ERR_PANIC, USAGEBAR_ERR_ARGS (null pointers).
int32_t usagebar_line_fields(const UsageBarNeedles *needles, const uint8_t *line, size_t len,
                          UsageBarLineFields *out);
/* UsageBarScanLine.kind. The history bits are set only for a line with no full-path needle. */
#define USAGEBAR_LINE_HISTORY_CANDIDATE 1u /* stamp earlier than since */
#define USAGEBAR_LINE_HISTORY_UNDECIDED 2u /* stamp the core does not parse: Swift asks its formatters */
#define USAGEBAR_LINE_SIDECHAIN 4u        /* set only with a history bit: history needle 0 */
#define USAGEBAR_LINE_TYPE_ASSISTANT 8u   /* needle 1 */
#define USAGEBAR_LINE_TYPE_USER 16u       /* needle 2 */

typedef struct {
    UsageBarLineFields fields;  /* spans relative to the line */
    int64_t off;             /* the line in the block's bytes */
    int64_t len;             /* no trailing newline */
    uint32_t kind;           /* USAGEBAR_LINE_* */
    int32_t reserved;
} UsageBarScanLine;

typedef struct {
    uint64_t start_offset;   /* where the read began (0 when truncated) */
    uint64_t new_offset;     /* just past the last complete newline */
    uint64_t end;            /* the file size when it was opened */
    int32_t at_end;          /* the read reached the end of the file */
    int32_t truncated;       /* end < offset: the caller resets before applying any line */
    uint8_t *bytes;          /* what this tick read; lines and tail point into it */
    size_t bytes_len;
    UsageBarScanLine *lines;
    size_t line_count;
    UsageBarScanLine tail;      /* at_end: the bytes after the last newline, when has_tail */
    int32_t has_tail;
    int32_t reserved;
} UsageBarScanBlock;

/// One tick of `sawCapHit`. history_needles: sidechain, type assistant, type user, then the
/// full-path needles. since_reference is `since.timeIntervalSinceReferenceDate`, since_key
/// `transcriptSecondKey(since)`. 0 ok (free the block with usagebar_scan_block_free),
/// USAGEBAR_ERR_NOFILE (cannot open), USAGEBAR_ERR_ARGS, USAGEBAR_ERR_PANIC.
int32_t usagebar_scan_read(const UsageBarNeedles *line_needles, const UsageBarNeedles *history_needles,
                        const char *path, uint64_t offset, uint64_t budget_bytes,
                        uint64_t block_bytes, double since_reference, const uint8_t *since_key,
                        size_t since_key_len, UsageBarScanBlock *out);
void usagebar_scan_block_free(UsageBarScanBlock *block);
/// Build marker: the release script looks for this string in both CLI slices.
const char *usagebar_core_version(void);
#endif
