# Changelog

# Changelog

## v3.53.4-r1

Same SQLite release, rebuilt. The changes are in how it was compiled and in the
scripts around it.

### Fixed — the build

- **`SQLITE_SECURE_DELETE` was enabled in every previous build.** The flag was
  passed as `-DSQLITE_SECURE_DELETE=0`, but SQLite tests it with `#ifdef`, not
  by value:

  ```c
  /* btree.c */
  #if defined(SQLITE_SECURE_DELETE)
      pBt->btsFlags |= BTS_SECURE_DELETE;
  ```

  Defining it as `0` still defines it. Every `DELETE` was zero-filling its
  freed pages and every `VACUUM` was doing extra write work — the exact
  opposite of what the documentation claimed. The flag is now omitted
  entirely. Use `PRAGMA secure_delete=ON` per connection if you want it, or
  `SQLITE_FAST_SECURE_DELETE` for the cheaper in-page variant.

- **Two flags did nothing at all.** `SQLITE_ENABLE_JSON1` and
  `SQLITE_ENABLE_DESERIALIZE` appear nowhere in the SQLite source any more —
  JSON has been built in since 3.38 and deserialize since 3.36 (you disable it
  with `SQLITE_OMIT_DESERIALIZE`). Both were removed. Nothing is lost; the
  features were always there. The old docs told you to verify them with
  `sqlite_compileoption_used()`, which returned 0 and looked like a broken
  build.

- **`liblog.so` was linked but never used.** `readelf` showed it as a `NEEDED`
  dependency while the binary contained no `__android_log_*` symbol at all.
  `-Wl,--as-needed` drops it.

- **The version decoder was wrong.** `sqlite-amalgamation-3530400.zip` has no
  dots, so the `grep -oP '\d+\.\d+\.\d+'` never matched and the fallback did
  `minor = (v % 1000000) / 1000`, printing **3.530.400** instead of 3.53.4.
  The packed format is `XYYZZPP`; the decoder now handles it correctly.

- `SQLITE_MAX_EXPR_DEPTH=1000` was removed — that is already the default.

### Added — the build

- **Parallel sorter.** `SQLITE_MAX_WORKER_THREADS=4` and
  `SQLITE_DEFAULT_WORKER_THREADS=2`. Both were implicitly 0, which disabled
  parallel sorting entirely. Large `CREATE INDEX` and `ORDER BY` get faster on
  a multi-core phone.
- `SQLITE_ENABLE_SORTER_REFERENCES` — less memory when sorting wide rows.
- `SQLITE_ENABLE_SNAPSHOT`, `SQLITE_ENABLE_RBU`.
- `HAVE_MALLOC_USABLE_SIZE=1` — bionic has it.
- `SQLITE_TEMP_STORE=2` instead of `3`. Three forces temp tables into memory
  unconditionally and ignores `PRAGMA temp_store`, which can OOM the process
  on a large temp table.
- `SQLITE_ENABLE_STMT_SCANSTATUS` is now **opt-in** (`WITH_SCANSTATUS=1
  ./build.sh`). It adds counters to every `sqlite3_step()` whether you use
  `.scanstats` or not.
- Hardening and packaging: `-Wl,-z,relro`, `-Wl,-z,now`,
  `-Wl,-z,common-page-size=16384` alongside the existing `max-page-size` for
  16 KB page devices.

- **`build.sh` now verifies its own output.** After linking it reads the
  compile-option list back out of the binary and asserts that every expected
  option is present and that `SECURE_DELETE` is absent, checks the ELF
  architecture, PIE status, 16 KB segment alignment and the `NEEDED` library
  list, and refuses to finish if anything is off. It also writes `SHA256SUMS`,
  auto-detects the NDK from `ANDROID_NDK_HOME`/`ANDROID_NDK_ROOT`, and can
  install straight into a module tree with `--install DIR`, bumping
  `module.prop` for you.

### Fixed — the tools

- **`sqlite3-tool backup` used `cp`.** The comment claimed it used SQLite's
  online backup API; the code ran `wal_checkpoint(FULL)` and then copied the
  file. That writes to the source (so it fails on a read-only database) and is
  not atomic — a concurrent writer produces a corrupt backup. It now uses
  `.backup`, which is the real online backup API, and verifies the result with
  `integrity_check` before reporting success.
- **`sqlite3-tool restore` copied `-wal` and `-shm` from the backup.** A stale
  `-shm` next to a restored database is at best useless and at worst harmful.
  They are now deleted at the destination instead.
- **Neither tool set a busy timeout.** Both called `sqlite3.real` directly,
  bypassing the wrapper, so the first query against any live database returned
  `database is locked` immediately. Every command now sets one
  (`SQLITE3_BUSY_MS`, default 5000).
- **Table names were interpolated into SQL unquoted.** A table named
  `weird "quoted" name` broke every row count. Identifiers and string literals
  are now escaped properly.
- **Colours never worked.** Both scripts tested `[ "$(tput colors)" -ge 8 ]`,
  but Android's toybox has no `tput`, so the test always failed silently and
  the whole colour block was dead. They use `TERM` now, and honour `NO_COLOR`.
- **`sqlite3-doctor` ran `dd` twice** and threw the first result away
  (`MAGIC=$(dd ...)` was assigned and never used). The header check is a single
  `head -c 15` now.
- `sqlite3-doctor` always exited 0. It now exits 1 when it finds problems, so
  it can be used in a script.

### Added — the tools

- `sqlite3-tool biggest <db> [n]` — largest tables and indexes on disk via
  `dbstat`. This is the part of `sqlite3_analyzer` people actually want;
  `sqlite3_analyzer` itself needs TCL to build and was never shipped, though
  `customize.sh` checked for it.
- `sqlite3-tool compile-options [filter]` — see exactly how your `sqlite3` was
  built.
- `sqlite3-tool version`.
- `sqlite3-doctor --quick` (skip `integrity_check` and row counts) and
  `--full`. Row counts are skipped automatically on databases over 256 MB
  unless `--full` is given, so the doctor no longer takes minutes by surprise.
- Both tools honour `SQLITE3_BIN`, which also makes them testable against any
  sqlite3 build.

### Changed — the wrapper

`/system/bin/sqlite3` injected nine PRAGMAs. Five of them just repeated a
compile-time default that already applies to every connection, and the rest are
reset the moment you run `.open` inside the shell, because that creates a new
connection. Only two are worth setting: `busy_timeout`, which has no
compile-time equivalent, and `mmap_size`, which is scaled to the device.
The rest are gone, along with a fork per invocation. `SQLITE3_NO_WRAPPER=1`
bypasses it entirely.

The `.open` caveat is now documented rather than silently not working.

### Other

- `customize.sh` now refuses to install a broken package instead of installing
  it and failing later. It aborts if `sqlite3` or `sqlite3.real` is missing from
  the zip, and aborts if the shipped binary will not execute on the device
  (wrong architecture or corrupt file), printing `uname -m` and
  `ro.product.cpu.abi` so the report is actionable. `sqldiff`, `sqlite3-tool`
  and `sqlite3-doctor` are treated as optional and only warn. It also warns when
  `module.prop` and the binary disagree about the version — the signature of a
  package assembled from mismatched parts — and when the build has
  `SECURE_DELETE` on. The architecture check reads `ro.product.cpu.abi` as well
  as `uname -m`, and the dead `sqlite3_analyzer` branch is gone.
- `service.sh` rebuilds `module.prop` with a read loop instead of `sed -i`, and
  only when the status text actually changed.
- `uninstall.sh` no longer tries to delete `/.sqliterc-full` in the filesystem
  root — nothing ever created it.
- `files/sqliterc-full` documents which PRAGMAs are already compiled in, so it
  no longer suggests setting things that are set.
- The WebUI no longer requests Google Fonts (it fails on a device with no
  network), uses `viewport-fit=cover` with safe-area padding, and its flag
  table now matches the binary.

---

## v3.53.4

- Updated SQLite to version 3.53.4.
- Includes the latest upstream bug fixes and stability improvements.

---

## v3.53.3

> SQLite 3.53.3 — 2026-06-26

Bugfix patch release. No new features.

Fixes for problems in 3.53.0 / 3.53.1 / 3.53.2, mostly reported by AI-generated issues.

---

**SQLite source info:**
- `SQLITE_SOURCE_ID`: `2026-06-26 20:14:12 d4c0e51e4aeb96955b99185ab9cde75c339e2c29c3f3f12428d364a10d782c62`
- `SHA3-256 (sqlite3.c)`: `28e484abdaa43630e34040ef6ed92be973a1ad54107803d8af5145b889c23ed7`

---

## v3.53.2-r1 — 2026-06-13

### SQLite
- Updated to **SQLite 3.53.2** (2026-06-03)

### New binaries
- **`sqldiff`** — official SQLite diff tool; outputs SQL to transform one database into another. Supports `--schema`, `--table`, `--summary`, `--transaction` and `--vtab` flags. Built from the same source with identical compile flags.

### New scripts
- **`sqlite3-doctor`** — full database diagnostics in one command. Checks file validity, WAL state, page info, freelist/fragmentation, `integrity_check`, `quick_check`, foreign key violations and table stats. Outputs a color-coded report with a summary at the end.
- **`sqlite3-tool`** — helper wrapper with 13 ready-to-use commands: `integrity`, `vacuum`, `analyze`, `optimize`, `wal-checkpoint`, `tables`, `indexes`, `schema`, `size`, `info`, `backup`, `restore`, `doctor`. Backup is WAL-aware: runs `wal_checkpoint(FULL)` and copies `-wal`/`-shm` files automatically.

### Build
- Added `build.sh` — fully automated build script. Drop the two SQLite zip archives (`sqlite-amalgamation-*.zip` and `sqlite-src-*.zip`) in the working directory and run `./build.sh`. Extracts sources, builds all binaries and writes results to `android-module/`. No manual steps required for future version updates.
- Added `SQLITE_ENABLE_STMTVTAB` and `SQLITE_ENABLE_BYTECODE_VTAB` compile flags (were missing in previous builds).

### Help page (`index.html`)
- Added **Tools** section with dedicated pages for `sqldiff`, `sqlite3-doctor` and `sqlite3-tool`.
- Added **Tools** tab to mobile navigation.
- Updated section numbering (Verify → 16, Uninstall → 17).

### Module
- `customize.sh` — updated to set permissions for all new binaries. Each binary is optional: if absent from the zip it is silently skipped, so older zips remain compatible.
- `uninstall.sh` — updated to clean up temp files created by `sqlite3-doctor` and `sqlite3-tool`.

---

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
