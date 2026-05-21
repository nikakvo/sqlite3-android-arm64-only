# SQLite3 — Android Arm64 Only

> Max-feature standalone build of SQLite for rooted Android devices.  
> Built from source using the Android NDK toolchain. Targets `/system/bin/sqlite3`.  
> Does **not** replace or interfere with the system `libsqlite.so`.

*Built and maintained by [Tears Burn](https://github.com/nikakvo)*

---

## Requirements

- Android with SukiSU Ultra / KernelSU / Magisk
- Magisk: Android 6.0+ (API 23+)
- KernelSU / SukiSU Ultra: Android 12+
- Arm64 device only

---

## What This Module Does

Installs a standalone, max-feature `sqlite3` binary to `/system/bin/sqlite3`.

- Replaces the stock `sqlite3` shell binary (if present) with a far more capable build
- Does **not** touch `libsqlite.so` — Android apps and the framework are completely unaffected
- Safe to uninstall at any time — no traces left behind

---

## Compile Flags

This binary is compiled with every stable, safe SQLite feature enabled.

### Core

| Flag | Description |
|------|-------------|
| `-DSQLITE_THREADSAFE=1` | Full mutex serialization. Safe for multi-threaded use. |
| `-DSQLITE_ENABLE_COLUMN_METADATA` | Access column names, table names, and origin info via API. |
| `-DSQLITE_SECURE_DELETE=1` | Overwrites deleted data with zeros. Better privacy. |
| `-DSQLITE_USE_URI=1` | Enables URI filenames (e.g. `file:db?mode=ro`). |

### Search & Indexing

| Flag | Description |
|------|-------------|
| `-DSQLITE_ENABLE_FTS5` | Full-Text Search engine. Fast text indexing and search. |
| `-DSQLITE_ENABLE_RTREE` | R-Tree spatial indexing. Useful for geo/bounding box queries. |
| `-DSQLITE_ENABLE_GEOPOLY` | Polygon-based geospatial extension. Builds on R-Tree. |
| `-DSQLITE_ENABLE_STAT4` | Enhanced query planner statistics. Smarter query optimization. |

### JSON & Math

| Flag | Description |
|------|-------------|
| `-DSQLITE_ENABLE_JSON1` | Full JSON support: `json_extract()`, `json_set()`, `json_array()`, `json_array_insert()` and more. |
| `-DSQLITE_ENABLE_MATH_FUNCTIONS` | Math functions: `sin()`, `cos()`, `sqrt()`, `pow()`, `log()` etc. |

### Virtual Tables

| Flag | Description |
|------|-------------|
| `-DSQLITE_ENABLE_DBSTAT_VTAB` | `dbstat` virtual table — database page statistics. |
| `-DSQLITE_ENABLE_BYTECODE_VTAB` | Exposes the bytecode of prepared statements as a virtual table. |
| `-DSQLITE_ENABLE_DBPAGE_VTAB` | Raw page inspection via `dbpage` virtual table. Useful for forensics. |
| `-DSQLITE_ENABLE_STMTVTAB` | `sqlite_stmt` virtual table — introspect all prepared statements. |
| `-DSQLITE_ENABLE_CARRAY` | C-array virtual table for efficient array binding. |

### Session & Sync

| Flag | Description |
|------|-------------|
| `-DSQLITE_ENABLE_SESSION` | Session extension — generate changesets for DB sync. |
| `-DSQLITE_ENABLE_PREUPDATE_HOOK` | Hook called before UPDATE/DELETE. Required for SESSION. |
| `-DSQLITE_ENABLE_DESERIALIZE` | Load a database from a blob into memory via `sqlite3_deserialize()`. |
| `-DSQLITE_ENABLE_UNLOCK_NOTIFY` | Unlock notification API for blocked connections. |

### Developer / Debug

| Flag | Description |
|------|-------------|
| `-DSQLITE_ENABLE_EXPLAIN_COMMENTS` | Human-readable comments in `EXPLAIN` output. |
| `-DSQLITE_ENABLE_NORMALIZE` | SQL statement normalization API. |
| `-DSQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` | Suppresses errors for unknown functions in `EXPLAIN`. |
| `-DSQLITE_SOUNDEX` | `soundex()` function for phonetic string matching. |
| `-DSQLITE_ENABLE_UPDATE_DELETE_LIMIT` | `DELETE ... LIMIT n` and `UPDATE ... LIMIT n` support. |

### Performance & Memory

| Flag | Description |
|------|-------------|
| `-DSQLITE_TEMP_STORE=3` | All temp tables stored in RAM. Faster on mobile. |
| `-DSQLITE_DEFAULT_MEMSTATUS=0` | Disables memory usage tracking. Reduces overhead. |
| `-DSQLITE_MAX_EXPR_DEPTH=0` | Unlimited expression nesting depth. |

### Security

| Flag | Description |
|------|-------------|
| `-DSQLITE_OMIT_LOAD_EXTENSION` | Disables dynamic `.so` extension loading. Safer on Android. |

---

## What Is NOT Included

| Feature | Reason |
|---------|--------|
| ICU Unicode support | Requires external ICU libs — complex static build, significant binary size increase |
| `libsqlite.so` replacement | Would interfere with Android framework and apps — never safe |
| readline/editline | Not available in standard NDK builds |

---

## Build Info

```
Toolchain : aarch64-linux-android21-clang (NDK)
Target    : aarch64 Android API 21+
Source    : SQLite amalgamation (sqlite3.c + shell.c)
Flags     : -O2
```

---

## Module Status

The module description updates dynamically on every boot via `post-fs-data.sh`:

```
Max-feature standalone build for Android Arm64 (v3.53.1 working 🌬🌬🌬)
```

---

## Verify After Install

Open Termux and run:

```sh
sqlite3 --version
```

Expected output:
```
3.53.1 2026-05-05 10:34:17 c88b22011a54b4f6fbd149e9f8e4de77658ce58143a1af0e3785e4e6475127e9
```

Test a feature — for example FTS5:

```sh
sqlite3 /tmp/test.db "CREATE VIRTUAL TABLE t USING fts5(content); INSERT INTO t VALUES('hello world'); SELECT * FROM t WHERE t MATCH 'hello';"
```

---

## Uninstall

Remove the module via SukiSU Ultra / KernelSU / Magisk and reboot.  
No config files, no leftover data, no system modifications outside the module directory.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
