# Changelog

v3.53.1-r2 — 2026-05-23
Build — Compiler Flags (new)

-fno-unwind-tables + -fno-asynchronous-unwind-tables — removes unwind/exception tables from binary. CLI tool doesn't need them. Standard for embedded builds, reduces binary size
-fmerge-all-constants — merges identical constants across compilation units. Small size reduction

Build — Linker Flags (new)

-Wl,-O2 — linker-level optimization on top of compiler -O3. Small additional gain, no downside

Build — SQLite Flags (new)

SQLITE_ENABLE_PERCENTILE — adds percentile(), percentile_cont(), percentile_disc() aggregate functions. Useful for median, P50/P95/P99 analytics directly in SQL
SQLITE_ENABLE_STMT_SCANSTATUS — enables runtime scan statistics per prepared statement. Useful for query profiling and planner analysis

Module

Updated webroot/help.html — new section for Percentile & Analytics with usage examples
All new r2 flags documented with descriptions
Build command updated to r2 final

## v3.53.1-r1 — 2026-05-23
Build — Compiler & Linker

Upgraded from -O2 to -O3 — maximum Clang optimization (full inlining, loop unrolling, vectorization)
Added -march=armv8-a — native ARMv8-A instruction set targeting
Added -flto — Link-Time Optimization, cross-file dead code elimination
Added -fomit-frame-pointer, -fvisibility=hidden, -ffunction-sections, -fdata-sections
Added linker flags: --gc-sections, --strip-all, -z,max-page-size=16384
The last flag is required for Android 15 devices with 16KB memory pages

Build — SQLite Flags (new)

SQLITE_DQS=0 — stricter SQL parser, disables legacy double-quoted string behavior
SQLITE_LIKE_DOESNT_MATCH_BLOBS — correctness and small perf win
SQLITE_STMTJRNL_SPILL=-1 — statement journals stay in RAM, no disk spill
SQLITE_DEFAULT_CACHE_SIZE=-16000 — ~16MB page cache
SQLITE_DEFAULT_WAL_SYNCHRONOUS=1 — NORMAL sync for WAL mode by default
SQLITE_DEFAULT_SYNCHRONOUS=1 — NORMAL sync for default journal mode
SQLITE_ENABLE_API_ARMOR — runtime checks for invalid API usage
SQLITE_ENABLE_NULL_TRIM — smaller rows by trimming trailing NULLs
SQLITE_HAVE_ISNAN + HAVE_USLEEP=1 — Android platform compatibility

Build — SQLite Flags (changed)

SQLITE_SECURE_DELETE — changed from =1 to =0. Was causing unnecessary write amplification on flash storage. Use PRAGMA secure_delete=ON at runtime if needed
SQLITE_MAX_EXPR_DEPTH — changed from =0 (unlimited) to =1000. Prevents stack overflow on deeply nested or malformed SQL

Module

Updated webroot/help.html — full local help page, no longer redirects to GitHub
Added Compiler & Linker Flags section to documentation
All new/changed flags documented with descriptions and rationale
Mobile navigation fixed — sticky bottom nav bar with section drawer

## v3.53.1 — 2026-05-21

- Initial release
- SQLite 3.53.1 compiled from source via Android NDK
- Max-feature standalone build for Arm64
- All stable compile flags enabled
- WebUI redirect to GitHub documentation
- Dynamic status in module description via post-fs-data.sh
