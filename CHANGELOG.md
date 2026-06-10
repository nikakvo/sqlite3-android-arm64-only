# Changelog

## v3.53.2 — 2026-06-03

### Initial Release

- SQLite 3.53.2 built from official amalgamation source
- Android NDK, API 21+, ARM64 target (`-march=armv8-a`)
- PIE binary with `-fstack-protector-strong` and LLD linker
- 16 KB page alignment for Android 15+ compatibility (`-Wl,-z,max-page-size=16384`)

**Wrapper architecture:**
- `sqlite3` is a shell script wrapper; `sqlite3.real` is the compiled binary
- Adaptive `mmap_size` detection from `/proc/meminfo` at startup (64 / 128 / 256 MB)
- Session PRAGMAs injected via `-cmd` — no `$HOME` or `.sqliterc` dependency

**Session defaults applied automatically:**
- `cache_size = -20000` (~20 MB page cache)
- `temp_store = MEMORY`
- `busy_timeout = 5000`
- `synchronous = NORMAL`
- `wal_autocheckpoint = 500`
- `foreign_keys = ON`
- `recursive_triggers = ON`
- `analysis_limit = 1000`

**Extensions enabled:**
- FTS4 (includes FTS3) + FTS3 Parenthesized Queries + FTS5
- JSON1, RTREE, GEOPOLY
- SESSION + PREUPDATE HOOK + DESERIALIZE + UNLOCK NOTIFY
- DBSTAT, DBPAGE, BYTECODE, STMTVTAB, CARRAY virtual tables
- MATH FUNCTIONS, PERCENTILE, STAT4
- API ARMOR, STMT SCAN STATUS, NORMALIZED SQL, SOUNDEX, and more

**Deployed files:**
- `/system/bin/sqlite3` — wrapper script
- `/system/bin/sqlite3.real` — compiled binary
- `/data/local/.sqliterc-full` + `/.sqliterc-full` — full reference config
- `uninstall.sh` — removes all deployed files on uninstall
