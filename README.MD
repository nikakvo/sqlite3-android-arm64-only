# SQLite3 Android ARM64 Only

A standalone **max-feature SQLite3 shell** for rooted Android ARM64 devices.

Built directly from the official SQLite source tree using the Android NDK and packaged as a Magisk / KernelSU / SukiSU Ultra / APatch module. Replaces only the interactive `sqlite3` command-line shell — Android's system `libsqlite.so` is completely untouched.

---

## Features

- Official upstream SQLite **3.53.4** build, verified after linking
- ARM64-only, compiled with Android NDK (API 21+)
- Wrapper + real binary architecture (`sqlite3` → `sqlite3.real`)
- Adaptive `mmap_size` — 64 / 128 / 256 / 512 MB depending on device RAM
- Parallel sorter enabled — faster `CREATE INDEX` and large `ORDER BY`
- Ships **`sqldiff`**, **`sqlite3-tool`** and **`sqlite3-doctor`**
- 16 KB page-size aligned, PIE, RELRO + BIND_NOW
- Offline documentation in the module's WebUI
- Safe to uninstall — `uninstall.sh` cleans up all deployed files
- Android framework and installed applications remain completely unaffected

---

## Included SQLite Extensions

Nearly every stable compile-time feature available in SQLite is enabled:

| Category | Extensions |
|---|---|
| Full-Text Search | FTS4 (includes FTS3), FTS5, FTS3 Parenthesized Queries |
| Geospatial | RTREE, GEOPOLY |
| Sync & Bulk | SESSION, PREUPDATE HOOK, SNAPSHOT, RBU, UNLOCK NOTIFY |
| Virtual Tables | DBSTAT, DBPAGE, BYTECODE, STMTVTAB, CARRAY |
| Math & Stats | MATH FUNCTIONS, PERCENTILE, STAT4, SORTER REFERENCES |
| Developer | API ARMOR, NORMALIZED SQL, COLUMN METADATA, SOUNDEX, UPDATE/DELETE LIMIT, EXPLAIN COMMENTS, OFFSET SQL FUNC, NULL TRIM, UNKNOWN SQL FUNCTION |

> **JSON and `sqlite3_deserialize()` are present** but no longer listed as flags. `SQLITE_ENABLE_JSON1` and `SQLITE_ENABLE_DESERIALIZE` stopped existing in SQLite years ago — JSON has been built in since 3.38, deserialize since 3.36. Passing those flags did nothing, and `sqlite_compileoption_used()` on them returns 0, which looks like a broken build. Test the features, not the flags.

> **FTS4 and FTS5 are separate engines.** FTS4 is included because Android system databases (contacts, calendar, SMS) use FTS4 tables. FTS5 is a completely independent rewrite with BM25 ranking and prefix queries.

> **`STMT_SCANSTATUS` is opt-in.** It adds counters to every `sqlite3_step()` call whether you use `.scanstats` or not. Rebuild with `WITH_SCANSTATUS=1 ./build.sh` if you want it.

---

## Included Tools

| Tool | Purpose |
|---|---|
| `sqlite3` | wrapper that sets a busy timeout and a RAM-scaled `mmap_size` |
| `sqlite3.real` | the compiled binary |
| `sqldiff` | official SQLite tool — diff two databases |
| `sqlite3-tool` | 16 helper commands for inspection and maintenance |
| `sqlite3-doctor` | full database diagnostic, exits non-zero on problems |

### sqlite3-tool

```
Inspect:   info · tables · indexes · schema · size · biggest · doctor
Maintain:  integrity · vacuum · analyze · optimize · wal-checkpoint
Data:      backup · restore
Build:     compile-options · version
```

`backup` uses SQLite's **online backup API** (`.backup`), so it is safe on a live database, needs no write access to the source, and the result is verified with `integrity_check` before the command reports success.

`biggest <db> [n]` lists the largest tables and indexes on disk via `dbstat` — the part of `sqlite3_analyzer` people actually want, without needing TCL to build it.

```sh
sqlite3-tool info /data/data/com.example/databases/app.db
sqlite3-tool backup /data/data/com.example/databases/app.db /sdcard/app.db
sqlite3-tool biggest /sdcard/big.db 10
sqlite3-tool compile-options WORKER
```

Environment: `SQLITE3_BIN`, `SQLITE3_BUSY_MS` (default 5000), `NO_COLOR`.

### sqlite3-doctor

```sh
sqlite3-doctor [--quick|--full] <database.db>
```

Header validation, WAL state, page and freelist analysis, `quick_check`, `integrity_check`, `foreign_key_check` and per-table row counts. Row counts are skipped on databases over 256 MB unless `--full` is given; `--quick` skips `integrity_check` and row counts entirely. Exits 1 when it finds problems, so it works in scripts.

---

## Wrapper Architecture

The installed `/system/bin/sqlite3` is a lightweight shell script wrapper. On every invocation it:

1. Reads `/proc/meminfo` to detect device RAM
2. Selects an appropriate `mmap_size` (64 / 128 / 256 / 512 MB)
3. Injects `busy_timeout` and `mmap_size` via `-cmd`
4. Calls the actual compiled binary — `sqlite3.real`

Set `SQLITE3_NO_WRAPPER=1` to bypass it entirely.

### Why only two PRAGMAs

Earlier versions injected nine. Five of them simply repeated a compile-time default that already applies to every connection:

| PRAGMA | Already guaranteed by |
|---|---|
| `temp_store` | `SQLITE_TEMP_STORE=2` |
| `synchronous` | `SQLITE_DEFAULT_SYNCHRONOUS=1` |
| `foreign_keys` | `SQLITE_DEFAULT_FOREIGN_KEYS=1` |
| `cache_size` | `SQLITE_DEFAULT_CACHE_SIZE=-16000` |
| `mmap_size` | `SQLITE_DEFAULT_MMAP_SIZE=256 MB` |

Only `busy_timeout` has no compile-time equivalent, and only `mmap_size` benefits from being scaled to the device. The rest cost a fork per invocation and bought nothing.

> **Important:** PRAGMAs set at startup belong to the connection open at that moment. Running `.open` inside the shell creates a **new** connection and resets `busy_timeout` and `mmap_size` back to the compiled defaults. Pass the database on the command line if you want the wrapper's settings to apply to it.

---

## Compile-Time Defaults

Applied to every connection automatically, no configuration needed:

| Setting | Value |
|---|---|
| `THREADSAFE` | 1 (full mutex serialization) |
| `TEMP_STORE` | 2 — memory by default, `PRAGMA temp_store` can override |
| `DEFAULT_CACHE_SIZE` | -16000 (~16 MB) |
| `DEFAULT_SYNCHRONOUS` | 1 (NORMAL) |
| `DEFAULT_WAL_SYNCHRONOUS` | 1 (NORMAL) |
| `DEFAULT_FOREIGN_KEYS` | 1 (ON) |
| `DEFAULT_MMAP_SIZE` | 256 MB |
| `MAX_MMAP_SIZE` | 1 TB |
| `MAX_WORKER_THREADS` | 4 |
| `DEFAULT_WORKER_THREADS` | 2 |
| `DQS` | 0 (no double-quoted string literals) |
| `OMIT_LOAD_EXTENSION` | yes (smaller attack surface) |
| `SECURE_DELETE` | **off** — see below |

---

## `.sqliterc-full`

The module deploys an annotated reference configuration to:

```
/data/local/.sqliterc-full
```

It documents every tunable PRAGMA, marks which ones are already compiled in, and covers advanced options like `page_size`, `locking_mode`, `auto_vacuum`, `secure_delete` and device-class mmap tuning. Everything beyond the base block is commented out.

```sh
sqlite3 -init /data/local/.sqliterc-full /path/to/database.db
```

---

## Installation

1. Download the latest `.zip` from [Releases](https://github.com/nikakvo/sqlite3-android-arm64-only/releases)
2. Install via **Magisk**, **KernelSU**, **SukiSU Ultra** or **APatch**
3. Reboot
4. Verify:

```sh
sqlite3 --version
sqlite3-tool version
sqlite3 :memory: "SELECT sqlite_compileoption_used('SECURE_DELETE');"   # 0
```

The installer refuses to continue if the package is incomplete or if the shipped binary will not execute on your device, rather than installing something that fails later.

<img width="300" alt="sqlite3" src="https://raw.githubusercontent.com/nikakvo/sqlite3-android-arm64-only/main/Sqlite3.jpg" />

## Requirements

| Requirement | Details |
|---|---|
| Architecture | ARM64 only |
| Root manager | Magisk · KernelSU · SukiSU Ultra · APatch |
| Android (Magisk) | 6.0+ (API 23+) |
| Android (KernelSU / SukiSU) | 12+ |
| WebUI | needs a manager that renders `webroot` (KernelSU, SukiSU, APatch, MMRL) |

---

## Building

```sh
# put sqlite-amalgamation-*.zip and sqlite-src-*.zip next to build.sh
export ANDROID_NDK_HOME=/path/to/android-ndk
./build.sh                              # -> ./android-module/
./build.sh --install /path/to/module    # also copies in and bumps module.prop
```

Key compiler flags:

```
-O2 -march=armv8-a -fPIE -pie -fuse-ld=lld
-fstack-protector-strong -ffunction-sections -fdata-sections
-Wl,--gc-sections -Wl,--as-needed -Wl,--strip-all
-Wl,-z,relro -Wl,-z,now
-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
```

The full flag list, with a note on what each one does, is in the module's built-in help page (`webroot/index.html`).

### The build verifies itself

After linking, `build.sh` reads the compile-option list back out of the finished binary and asserts that every expected flag is present and that `SECURE_DELETE` is absent, then checks the ELF architecture, PIE status, 16 KB segment alignment and the `NEEDED` library list. It refuses to finish if anything is off, and writes `SHA256SUMS`.

```
── Verifying the produced binary
  [OK]    all 47 compile-option assertions passed

── Linked libraries
  [INFO]  NEEDED: libm.so libc.so

── ELF checks
  [OK]    architecture: aarch64
  [OK]    position independent executable
  [OK]    16 KB page alignment
```

### If you edit the flags: `#ifdef`, not value

Many SQLite options are tested for existence, not for their value:

```c
/* btree.c */
#if defined(SQLITE_SECURE_DELETE)
    pBt->btsFlags |= BTS_SECURE_DELETE;
```

`-DSQLITE_SECURE_DELETE=0` therefore **enables** secure delete. Builds of this module up to v3.53.4 shipped that way by mistake — every `DELETE` was zero-filling its freed pages and every `VACUUM` was doing extra write work, while the documentation claimed the opposite. If you don't want a feature, leave the flag out entirely. The verification step exists to catch exactly this class of mistake.

---

## Safety

This module **does not replace or modify Android's internal SQLite library (`libsqlite.so`)**.

Only the standalone `sqlite3` command-line shell is replaced. All applications and the Android framework continue using the stock system library exactly as before.

---

## Module Info

| Property | Value |
|---|---|
| Module ID | `sqlite3-arm64-only` |
| Author | Tears Burn |
| Architecture | ARM64 |
| SQLite Version | 3.53.4 |
| Build Type | Standalone Max-Feature Shell |

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## Credits

- [SQLite Development Team](https://www.sqlite.org/)
- Android NDK

---

*Intended for developers, power users, database inspection, forensic analysis, and advanced Android maintenance workflows.*
