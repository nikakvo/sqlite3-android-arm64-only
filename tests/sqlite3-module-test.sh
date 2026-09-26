#!/system/bin/sh
# sqlite3-module-test.sh — functional test suite for sqlite3-android-arm64-only
# Part of nikakvo/sqlite3-android-arm64-only
#
# Tests the installed module end to end: the binary and its compile options,
# the sqlite3 wrapper, sqldiff, sqlite3-tool, sqlite3-doctor and, on a phone,
# the module installation itself. Run it after every new build.
#
# On the phone (Termux cannot execute scripts from /sdcard):
#   cp /sdcard/Download/sqlite3-module-test.sh ~/
#   su -c "sh /data/data/com.termux/files/home/sqlite3-module-test.sh"
#
# The full log is written to /sdcard/Download/sqlite3-module-test.log.
#
# Environment:
#   BIN_DIR   directory holding sqlite3, sqlite3.real, sqldiff, sqlite3-tool
#             and sqlite3-doctor (default /system/bin)
#   WORK      scratch directory (default /data/local/tmp/sqlite3-test.<pid>)
#   LOG       log file (default /sdcard/Download/sqlite3-module-test.log)
#   KEEP=1    keep the scratch directory
#   VERBOSE=1 print the output of every passing test too
#
# Exit status: 0 if every test passed, 1 otherwise.

SUITE_VERSION="1.0"
MOD_ID="sqlite3-arm64-only"

BIN_DIR="${BIN_DIR:-/system/bin}"
[ -d /data/local/tmp ] && DEF_WORK="/data/local/tmp/sqlite3-test.$$" || DEF_WORK="${TMPDIR:-/tmp}/sqlite3-test.$$"
WORK="${WORK:-$DEF_WORK}"
if [ -z "${LOG:-}" ]; then
    if [ -d /sdcard/Download ] && [ -w /sdcard/Download ]; then
        LOG=/sdcard/Download/sqlite3-module-test.log
    else
        LOG="${TMPDIR:-/tmp}/sqlite3-module-test.log"
    fi
fi

WRAP="$BIN_DIR/sqlite3"
REAL="$BIN_DIR/sqlite3.real"
DIFF="$BIN_DIR/sqldiff"
TOOL="$BIN_DIR/sqlite3-tool"
DOC="$BIN_DIR/sqlite3-doctor"

# The tools look for /system/bin/sqlite3.real; point them at the tested one.
export SQLITE3_BIN="$REAL"
export NO_COLOR=1
unset SQLITE3_NO_WRAPPER

RESULTS="$WORK/.results"

# ── Framework ─────────────────────────────────────────────────────────────────
pass() { echo "PASS" >> "$RESULTS"; printf '  [PASS] %s\n' "$1"; }
fail() {
    echo "FAIL" >> "$RESULTS"
    printf '  [FAIL] %s\n' "$1"
    [ -z "$2" ] || printf '%s\n' "$2" | head -n 15 | sed 's/^/           | /'
}
skip() { echo "SKIP" >> "$RESULTS"; printf '  [SKIP] %s\n' "$1"; }
section() { printf '\n== %s\n' "$1"; }

# t_eq <description> <expected> <actual>
t_eq() {
    if [ "$2" = "$3" ]; then
        pass "$1"
        [ "${VERBOSE:-0}" = "1" ] && printf '%s\n' "$3" | sed 's/^/           | /'
    else
        fail "$1" "expected: [$2]
got:      [$3]"
    fi
}

# t_has <description> <needle> <haystack>
t_has() {
    case "$3" in
        *"$2"*) pass "$1" ;;
        *) fail "$1" "missing: [$2]
in:      [$3]" ;;
    esac
}

# t_rc <description> <expected-rc> <command...>
t_rc() {
    _d="$1"; _want="$2"; shift 2
    _out=$("$@" 2>&1); _got=$?
    if [ "$_got" = "$_want" ]; then pass "$_d"
    else fail "$_d" "exit status $_got, wanted $_want
$_out"
    fi
}

# q <sql...> — run SQL on an in-memory database with the raw binary
q() { "$REAL" -batch :memory: "$@" 2>&1; }

# ── Test groups ───────────────────────────────────────────────────────────────
test_files() {
    section "Files"
    for f in sqlite3 sqlite3.real sqldiff sqlite3-tool sqlite3-doctor; do
        if [ -x "$BIN_DIR/$f" ]; then pass "$f is present and executable"
        else fail "$f is present and executable" "$BIN_DIR/$f"
        fi
    done
    [ -x "$REAL" ] || { fail "cannot continue without sqlite3.real"; return 1; }
    V=$("$REAL" --version 2>&1)
    case "$V" in
        3.*) pass "sqlite3.real runs: $(printf '%s' "$V" | cut -d' ' -f1)" ;;
        *) fail "sqlite3.real runs" "$V"; return 1 ;;
    esac
}

test_compile_options() {
    section "Compile options"
    OPTS=$(q "PRAGMA compile_options;")
    for o in THREADSAFE=1 USE_URI OMIT_LOAD_EXTENSION DQS=3 LIKE_DOESNT_MATCH_BLOBS \
             TEMP_STORE=2 DEFAULT_MEMSTATUS=0 DEFAULT_CACHE_SIZE=-16000 STMTJRNL_SPILL=-1 \
             DEFAULT_WAL_SYNCHRONOUS=1 DEFAULT_SYNCHRONOUS=1 DEFAULT_FOREIGN_KEYS \
             DEFAULT_MMAP_SIZE=268435456 MAX_MMAP_SIZE=1099511627776 \
             MAX_WORKER_THREADS=4 DEFAULT_WORKER_THREADS=2 ENABLE_SORTER_REFERENCES \
             ENABLE_FTS3_PARENTHESIS ENABLE_FTS4 ENABLE_FTS5 ENABLE_RTREE ENABLE_GEOPOLY \
             ENABLE_STAT4 ENABLE_MATH_FUNCTIONS ENABLE_PERCENTILE ENABLE_OFFSET_SQL_FUNC \
             ENABLE_SESSION ENABLE_PREUPDATE_HOOK ENABLE_SNAPSHOT ENABLE_RBU \
             ENABLE_UNLOCK_NOTIFY ENABLE_DBSTAT_VTAB ENABLE_DBPAGE_VTAB ENABLE_STMTVTAB \
             ENABLE_BYTECODE_VTAB ENABLE_CARRAY ENABLE_COLUMN_METADATA ENABLE_NORMALIZE \
             ENABLE_EXPLAIN_COMMENTS ENABLE_UNKNOWN_SQL_FUNCTION ENABLE_NULL_TRIM \
             ENABLE_API_ARMOR SOUNDEX ENABLE_UPDATE_DELETE_LIMIT; do
        # DEFAULT_FOREIGN_KEYS is reported with or without "=1" depending on version
        if printf '%s\n' "$OPTS" | grep -qx -e "$o" -e "$o=1"; then pass "has $o"
        else fail "has $o"
        fi
    done
    for o in SECURE_DELETE FAST_SECURE_DELETE OMIT_JSON OMIT_DESERIALIZE; do
        if printf '%s\n' "$OPTS" | grep -qx "$o"; then fail "does not have $o"
        else pass "does not have $o"
        fi
    done
}

test_defaults() {
    section "Connection defaults (compile-time)"
    t_eq "foreign_keys = 1"        "1"      "$(q 'PRAGMA foreign_keys;')"
    t_eq "secure_delete = 0"       "0"      "$(q 'PRAGMA secure_delete;')"
    t_eq "synchronous = 1 (NORMAL)" "1"     "$(q 'PRAGMA synchronous;')"
    t_eq "cache_size = -16000"     "-16000" "$(q 'PRAGMA cache_size;')"
    t_eq "threads = 2"             "2"      "$(q 'PRAGMA threads;')"
    t_eq "busy_timeout = 0 without wrapper" "0" "$(q 'PRAGMA busy_timeout;')"
    D="$WORK/defaults.db"
    "$REAL" "$D" "CREATE TABLE t(x);" >/dev/null 2>&1
    t_eq "mmap_size = 256 MB on a file database" "268435456" "$("$REAL" "$D" 'PRAGMA mmap_size;' 2>&1)"
}

test_features() {
    section "SQL features"
    t_eq "FTS5" "hello world" "$(q "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES('hello world'),('bye'); SELECT c FROM t WHERE t MATCH 'hel*';")"
    t_eq "FTS5 bm25 + highlight" "[hello] world" "$(q "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES('hello world'); SELECT highlight(t,0,'[',']') FROM t WHERE t MATCH 'hello' ORDER BY bm25(t);")"
    t_eq "FTS4 enhanced query syntax" "hello world" "$(q "CREATE VIRTUAL TABLE t USING fts4(c); INSERT INTO t VALUES('hello world'); SELECT c FROM t WHERE t MATCH 'hello AND (world OR earth)';")"
    t_eq "FTS3 table" "1" "$(q "CREATE VIRTUAL TABLE t USING fts3(c); INSERT INTO t VALUES('abc'); SELECT count(*) FROM t WHERE t MATCH 'abc';")"
    t_eq "R-Tree" "1" "$(q "CREATE VIRTUAL TABLE g USING rtree(id,a,b); INSERT INTO g VALUES(1,0,10); SELECT id FROM g WHERE a<=5 AND b>=5;")"
    t_eq "Geopoly" "A" "$(q "CREATE VIRTUAL TABLE z USING geopoly(name); INSERT INTO z(name,_shape) VALUES('A','[[0,0],[1,0],[1,1],[0,1],[0,0]]'); SELECT name FROM z WHERE geopoly_contains_point(_shape,0.5,0.5);")"
    t_eq "JSON" "1" "$(q "SELECT json_extract('{\"a\":1}','\$.a');")"
    t_eq "JSONB" "1" "$(q "SELECT jsonb('{\"a\":1}') ->> '\$.a';")"
    t_eq "json_each" "3" "$(q "SELECT count(*) FROM json_each('[1,2,3]');")"
    t_eq "math functions" "1.0" "$(q 'SELECT round(ln(exp(1)),6);')"
    t_eq "percentile / median" "2.0" "$(q 'SELECT median(column1) FROM (VALUES(1),(2),(9));')"
    t_eq "percentile()" "5.0" "$(q 'SELECT percentile(column1,50) FROM (VALUES(1),(5),(9));')"
    t_eq "soundex" "R163" "$(q "SELECT soundex('Robert');")"
    t_eq "window functions" "1|2|3" "$(q "SELECT group_concat(r,'|') FROM (SELECT row_number() OVER (ORDER BY x) r FROM (SELECT 3 x UNION SELECT 1 UNION SELECT 2));")"
    t_eq "RETURNING" "7" "$(q 'CREATE TABLE a(x); INSERT INTO a VALUES(7) RETURNING x;')"
    t_eq "UPSERT" "2" "$(q 'CREATE TABLE a(k PRIMARY KEY,v); INSERT INTO a VALUES(1,1); INSERT INTO a VALUES(1,1) ON CONFLICT(k) DO UPDATE SET v=v+1; SELECT v FROM a;')"
    t_has "STRICT tables reject bad types" "cannot store TEXT value in INTEGER column" \
        "$(q "CREATE TABLE a(x INTEGER) STRICT; INSERT INTO a VALUES('abc');")"
    t_eq "generated columns" "4" "$(q 'CREATE TABLE a(x, y AS (x*2)); INSERT INTO a(x) VALUES(2); SELECT y FROM a;')"
    t_eq "DELETE ... ORDER BY ... LIMIT" "2,3" "$(q 'CREATE TABLE a(x); INSERT INTO a VALUES(1),(2),(3); DELETE FROM a ORDER BY x LIMIT 1; SELECT group_concat(x) FROM a;')"
    t_eq "UPDATE ... ORDER BY ... LIMIT" "1,2,30" "$(q 'CREATE TABLE a(x); INSERT INTO a VALUES(1),(2),(3); UPDATE a SET x=x*10 ORDER BY x DESC LIMIT 1; SELECT group_concat(x) FROM a;')"
    t_eq "double-quoted string literal (DQS=3)" "abc" "$(q 'SELECT "abc";')"
    t_eq "dbstat" "1" "$(q 'CREATE TABLE a(x); SELECT count(*)>0 FROM dbstat;')"
    t_eq "sqlite_dbpage" "1" "$(q 'CREATE TABLE a(x); SELECT count(*)>0 FROM sqlite_dbpage;')"
    t_eq "bytecode()" "1" "$(q "SELECT count(*)>0 FROM bytecode('SELECT 1');")"
    t_eq "sqlite_stmt" "1" "$(q 'SELECT count(*)>0 FROM sqlite_stmt;')"
    # $carray_primes is a test binding built into the sqlite3 shell
    t_eq "carray()" "26" "$(q 'SELECT count(*) FROM carray($carray_primes);')"
    t_eq "sqlite_offset()" "1" "$(q 'CREATE TABLE a(x); INSERT INTO a VALUES(1); SELECT sqlite_offset(x)>0 FROM a;')"
    t_eq "LIKE does not match BLOBs" "0" "$(q "SELECT x'616263' LIKE 'abc';")"
    t_has "load_extension is compiled out" "no such function: load_extension" "$(q "SELECT load_extension('x');")"
    t_has "EXPLAIN comments" "r[" "$(q '.explain off' 'EXPLAIN SELECT 1;')"
    t_eq "STAT4 fills sqlite_stat4" "1" "$(q 'CREATE TABLE a(x); CREATE INDEX i ON a(x); INSERT INTO a SELECT value%10 FROM generate_series(1,200); ANALYZE; SELECT count(*)>0 FROM sqlite_stat4;')"
    SESS=$(q '.help session')
    t_has ".session is available (SESSION)" ".session" "$SESS"
}

test_heavy() {
    section "Workload"
    H="$WORK/heavy.db"
    "$REAL" "$H" "PRAGMA journal_mode=WAL;" \
        "CREATE TABLE t(id INTEGER PRIMARY KEY, a TEXT, b REAL);" \
        "INSERT INTO t(a,b) SELECT hex(randomblob(16)), random()%1000 FROM generate_series(1,100000);" \
        "CREATE INDEX t_a ON t(a);" "CREATE INDEX t_b ON t(b);" >/dev/null 2>&1
    t_eq "100k rows + 2 indexes (parallel sorter)" "100000" "$("$REAL" "$H" 'SELECT count(*) FROM t INDEXED BY t_a;' 2>&1)"
    t_eq "integrity_check on the result" "ok" "$("$REAL" "$H" 'PRAGMA integrity_check;' 2>&1)"
    t_eq "ORDER BY over 100k rows" "100000" "$("$REAL" "$H" 'SELECT count(*) FROM (SELECT a FROM t NOT INDEXED ORDER BY a DESC, b);' 2>&1)"
    t_eq "VACUUM" "ok" "$("$REAL" "$H" 'VACUUM;' 'PRAGMA quick_check;' 2>&1)"
}

test_wrapper() {
    section "sqlite3 wrapper"
    W="$WORK/wrap.db"
    "$REAL" "$W" "CREATE TABLE t(x); INSERT INTO t VALUES(1),(2);" >/dev/null 2>&1
    t_eq "output has no PRAGMA noise" "2" "$("$WRAP" "$W" 'SELECT count(*) FROM t;' 2>&1)"
    t_eq "busy_timeout = 5000" "5000" "$("$WRAP" "$W" 'PRAGMA busy_timeout;' 2>&1)"
    RAM=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
    if   [ "$RAM" -lt 3145728 ];  then M=67108864
    elif [ "$RAM" -lt 6291456 ];  then M=134217728
    elif [ "$RAM" -lt 12582912 ]; then M=268435456
    else M=536870912
    fi
    t_eq "mmap_size scaled to RAM ($((RAM / 1024)) MB -> $((M / 1048576)) MB)" "$M" "$("$WRAP" "$W" 'PRAGMA mmap_size;' 2>&1)"
    t_eq "-mmap 0 caps the wrapper" "0" "$("$WRAP" -mmap 0 "$W" 'PRAGMA mmap_size;' 2>&1)"
    t_eq "SQL from stdin" "2" "$(echo 'SELECT count(*) FROM t;' | "$WRAP" "$W" 2>&1)"
    t_eq "-json" '[{"x":1},
{"x":2}]' "$("$WRAP" -json "$W" 'SELECT x FROM t;' 2>&1)"
    # CSV rows end in CRLF (RFC 4180)
    t_eq "-csv -header" "x
1
2" "$("$WRAP" -csv -header "$W" 'SELECT x FROM t;' 2>&1 | tr -d '\r')"
    t_eq "-readonly still reads" "2" "$("$WRAP" -readonly "$W" 'SELECT count(*) FROM t;' 2>&1)"
    t_has "-readonly blocks writes" "readonly" "$("$WRAP" -readonly "$W" 'INSERT INTO t VALUES(3);' 2>&1)"
    t_eq "-safe works after the wrapper's dot-commands" "2" "$("$WRAP" -safe "$W" 'SELECT count(*) FROM t;' 2>&1)"
    t_has "-safe still blocks .shell" "safe mode" "$("$WRAP" -safe "$W" '.shell echo x' 2>&1)"
    t_rc  "SQL error gives a non-zero exit status" 1 "$WRAP" "$W" 'SELECT nope FROM t;'
    # Regression: with SQL in a -cmd, the shell exits after that -cmd when
    # -bail is given, so the user's statement silently never ran (rc 0).
    t_rc  "-bail: SQL error gives a non-zero exit status" 1 "$WRAP" -bail "$W" 'SELECT nope FROM t;'
    "$WRAP" -bail "$W" 'INSERT INTO t VALUES(3);' >/dev/null 2>&1
    t_eq  "-bail: the statement really runs" "3" "$("$REAL" "$W" 'SELECT count(*) FROM t;' 2>&1)"
    "$REAL" "$W" 'DELETE FROM t WHERE x=3;' >/dev/null 2>&1
    t_eq  "-bail: busy_timeout still set" "5000" "$("$WRAP" -bail "$W" 'PRAGMA busy_timeout;' 2>&1)"
    t_eq  ".open keeps the RAM-scaled mmap_size" "$M" "$("$WRAP" :memory: ".open $W" 'PRAGMA mmap_size;' 2>&1)"
    t_eq  "a larger PRAGMA mmap_size is capped" "$M" "$("$WRAP" "$W" 'PRAGMA mmap_size=1099511627776;' 2>&1)"
    t_eq  "a larger -mmap raises the ceiling" "1073741824" "$("$WRAP" -mmap 1073741824 "$W" 'PRAGMA mmap_size;' 2>&1)"
    t_eq "--version passes through" "$("$REAL" --version)" "$("$WRAP" --version 2>&1)"
    t_eq "SQLITE3_NO_WRAPPER=1 bypasses it" "0" "$(SQLITE3_NO_WRAPPER=1 "$WRAP" "$W" 'PRAGMA busy_timeout;' 2>&1)"
    printf '.output /dev/null\nPRAGMA cache_size=-2000;\n.output stdout\n' > "$WORK/rc"
    t_eq "-init file runs, wrapper values still apply" "-2000|5000" "$("$WRAP" -init "$WORK/rc" "$W" 'SELECT (SELECT cache_size FROM pragma_cache_size)||"|"||(SELECT timeout FROM pragma_busy_timeout);' 2>&1)"
    "$WRAP" "$W" .dump > "$WORK/dump.sql" 2>&1
    rm -f "$WORK/dump.db"
    "$WRAP" "$WORK/dump.db" < "$WORK/dump.sql" >/dev/null 2>&1
    t_eq ".dump round trip" "2" "$("$WRAP" "$WORK/dump.db" 'SELECT count(*) FROM t;' 2>&1)"

    # A second connection holds the write lock for 2 s. Without a busy timeout
    # the raw binary fails at once; through the wrapper the write waits.
    L="$WORK/lock.db"
    "$REAL" "$L" "PRAGMA journal_mode=WAL;" "CREATE TABLE t(x);" >/dev/null 2>&1
    "$REAL" "$L" "BEGIN IMMEDIATE;" "INSERT INTO t VALUES(1);" ".shell sleep 2" "COMMIT;" >/dev/null 2>&1 &
    LPID=$!
    sleep 1
    t_has "raw binary: 'database is locked' while a writer holds the lock" "locked" "$("$REAL" "$L" 'INSERT INTO t VALUES(2);' 2>&1)"
    t_eq  "wrapper: waits for the lock and writes" "" "$("$WRAP" "$L" 'INSERT INTO t VALUES(3);' 2>&1)"
    wait "$LPID"
    "$REAL" "$L" "BEGIN EXCLUSIVE;" "INSERT INTO t VALUES(4);" ".shell sleep 2" "COMMIT;" >/dev/null 2>&1 &
    LPID=$!
    sleep 1
    t_rc  "sqlite3-tool waits for an exclusive lock" 0 "$TOOL" integrity "$L"
    wait "$LPID"
    "$REAL" "$L" "DELETE FROM t WHERE x=4;" >/dev/null 2>&1
    t_eq  "both writes that should land did" "1,3" "$("$REAL" "$L" 'SELECT group_concat(x) FROM (SELECT x FROM t ORDER BY x);' 2>&1)"
}

test_sqldiff() {
    section "sqldiff"
    A="$WORK/a.db"; B="$WORK/b.db"
    rm -f "$A" "$B"
    "$REAL" "$A" "CREATE TABLE t(id INTEGER PRIMARY KEY, v); INSERT INTO t VALUES(1,'a'),(2,'b');" >/dev/null 2>&1
    "$REAL" "$B" "CREATE TABLE t(id INTEGER PRIMARY KEY, v); INSERT INTO t VALUES(1,'a'),(2,'B'),(3,'c');" >/dev/null 2>&1
    t_eq "--summary" "t: 1 changes, 1 inserts, 0 deletes, 1 unchanged" "$("$DIFF" --summary "$A" "$B" 2>&1)"
    "$DIFF" "$A" "$B" > "$WORK/patch.sql" 2>&1
    "$REAL" "$A" < "$WORK/patch.sql" >/dev/null 2>&1
    t_eq "diff applied -> databases identical" "" "$("$DIFF" "$A" "$B" 2>&1)"
    t_rc "missing file is an error" 1 "$DIFF" "$A" "$WORK/nope.db"
}

test_tool() {
    section "sqlite3-tool"
    T="$WORK/tool.db"
    rm -f "$T"
    "$REAL" "$T" "CREATE TABLE \"we\"\"ird t'able\"(x); INSERT INTO \"we\"\"ird t'able\" VALUES(1),(2),(3);" \
        "CREATE TABLE plain(id INTEGER PRIMARY KEY, v); CREATE INDEX plain_v ON plain(v);" \
        "INSERT INTO plain(v) SELECT randomblob(200) FROM generate_series(1,500);" >/dev/null 2>&1

    OUT=$("$TOOL" info "$T" 2>&1)
    t_has "info: journal mode" "Journal mode:    delete" "$OUT"
    t_has "info: 2 tables" "Tables:          2" "$OUT"
    OUT=$("$TOOL" tables "$T" 2>&1)
    t_has "tables: quoted name counted" "we\"ird t'able" "$OUT"
    t_has "tables: row count" "3 rows" "$OUT"
    t_has "tables: 500 rows" "500 rows" "$OUT"
    t_has "indexes" "plain_v" "$("$TOOL" indexes "$T" 2>&1)"
    t_has "schema <table> includes its index" "CREATE INDEX plain_v ON plain(v);" "$("$TOOL" schema "$T" plain 2>&1)"
    t_rc  "schema <missing table> fails" 1 "$TOOL" schema "$T" nope
    t_has "size" "Page count:" "$("$TOOL" size "$T" 2>&1)"
    t_has "biggest (dbstat)" "plain" "$("$TOOL" biggest "$T" 3 2>&1)"
    t_rc  "integrity" 0 "$TOOL" integrity "$T"
    t_rc  "analyze" 0 "$TOOL" analyze "$T"
    t_rc  "optimize" 0 "$TOOL" optimize "$T"
    "$REAL" "$T" "DELETE FROM plain WHERE id > 100;" >/dev/null 2>&1
    t_has "vacuum shrinks the file" "VACUUM complete" "$("$TOOL" vacuum "$T" 2>&1)"
    t_has "wal-checkpoint on a rollback-journal db" "Not in WAL mode" "$("$TOOL" wal-checkpoint "$T" 2>&1)"
    "$REAL" "$T" "PRAGMA journal_mode=WAL;" >/dev/null 2>&1
    t_has "wal-checkpoint in WAL mode" "Checkpointed" "$("$TOOL" wal-checkpoint "$T" 2>&1)"

    mkdir -p "$WORK/bk dir"
    t_rc  "backup into a directory (with a space)" 0 "$TOOL" backup "$T" "$WORK/bk dir"
    t_eq  "backup copy is complete" "3" "$("$REAL" "$WORK/bk dir/tool.db" "SELECT count(*) FROM \"we\"\"ird t'able\";" 2>&1)"
    t_rc  "backup to a path with ' and \"" 0 "$TOOL" backup "$T" "$WORK/it's \"q\".db"
    t_rc  "backup refuses source = destination" 1 "$TOOL" backup "$T" "$T"
    t_eq  "... and the source is still intact" "ok" "$("$REAL" "$T" 'PRAGMA integrity_check;' 2>&1)"
    t_eq  "no temporary files left behind" "" "$(find "$WORK" -name '*.sqlite3-tool-*.tmp')"

    "$REAL" "$T" "DELETE FROM plain;" >/dev/null 2>&1
    t_rc  "restore" 0 "$TOOL" restore "$WORK/bk dir/tool.db" "$T"
    t_eq  "restored content is back" "100" "$("$REAL" "$T" 'SELECT count(*) FROM plain;' 2>&1)"
    t_rc  "restore refuses backup = destination" 1 "$TOOL" restore "$T" "$T"

    printf 'this is not a database, just some text\n' > "$WORK/text.db"
    t_rc  "refuses a non-SQLite file" 1 "$TOOL" info "$WORK/text.db"
    t_rc  "missing file" 1 "$TOOL" info "$WORK/missing.db"
    cp "$T" "$WORK/-dash.db"
    ( cd "$WORK" && t_rc "file name starting with '-'" 0 "$TOOL" integrity "-dash.db" )
    t_has "compile-options filter" "ENABLE_FTS5" "$("$TOOL" compile-options fts5 2>&1)"
    t_has "version" "sqlite3-tool" "$("$TOOL" version 2>&1)"
    t_rc  "unknown command fails" 1 "$TOOL" frobnicate "$T"
    t_rc  "--help" 0 "$TOOL" --help
}

test_doctor() {
    section "sqlite3-doctor"
    G="$WORK/good.db"
    rm -f "$G"
    "$REAL" "$G" "CREATE TABLE p(id INTEGER PRIMARY KEY); CREATE TABLE c(pid REFERENCES p(id)); INSERT INTO p VALUES(1); INSERT INTO c VALUES(1);" >/dev/null 2>&1
    t_rc  "healthy database -> exit 0" 0 "$DOC" "$G"
    t_rc  "--quick -> exit 0" 0 "$DOC" --quick "$G"

    F="$WORK/fk.db"
    cp "$G" "$F"
    "$REAL" "$F" "PRAGMA foreign_keys=OFF;" "INSERT INTO c VALUES(99);" >/dev/null 2>&1
    OUT=$("$DOC" "$F" 2>&1); RC=$?
    t_eq  "foreign key violation -> exit 1" "1" "$RC"
    t_has "... and it is reported" "Foreign key violations found" "$OUT"

    C="$WORK/corrupt.db"
    rm -f "$C"
    "$REAL" "$C" "CREATE TABLE t(x); INSERT INTO t SELECT randomblob(300) FROM generate_series(1,2000); CREATE INDEX i ON t(x);" >/dev/null 2>&1
    # Overwrite page 5 with garbage: the header stays valid, the b-tree does not.
    dd if=/dev/urandom of="$C" bs=4096 seek=4 count=1 conv=notrunc 2>/dev/null
    OUT=$("$DOC" "$C" 2>&1); RC=$?
    t_eq  "corrupt database -> exit 1" "1" "$RC"
    t_has "... integrity_check FAILED reported" "FAILED" "$OUT"

    printf 'not a db' > "$WORK/text2.db"
    t_rc  "non-SQLite file -> exit 1" 1 "$DOC" "$WORK/text2.db"
    : > "$WORK/empty.db"
    t_rc  "0-byte file -> exit 1" 1 "$DOC" "$WORK/empty.db"
    t_rc  "unknown option -> exit 1" 1 "$DOC" --bogus "$G"
    t_rc  "tool doctor delegates" 0 "$TOOL" doctor "$G"
}

test_module() {
    section "Module installation (phone only)"
    MODDIR="/data/adb/modules/$MOD_ID"
    if [ ! -d "$MODDIR" ]; then
        skip "module not installed at $MODDIR"
        return 0
    fi
    [ -f "$MODDIR/disable" ] && fail "module is not disabled"
    PROPV=$(sed -n 's/^version=//p' "$MODDIR/module.prop" | head -n 1)
    BASE="${PROPV#v}"; BASE="${BASE%%-*}"
    t_eq "module.prop version matches the binary" "$BASE" "$("$REAL" --version | cut -d' ' -f1)"
    t_has "service.sh status in module.prop" "working)" "$(grep '^description=' "$MODDIR/module.prop")"
    t_eq "module.prop keeps updateJson (last line)" "1" "$(grep -c '^updateJson=' "$MODDIR/module.prop")"
    t_eq "/data/local/.sqliterc-full deployed" "yes" "$([ -f /data/local/.sqliterc-full ] && echo yes)"
    # Not "command -v sqlite3": under su the PATH may still start with Termux's
    # bin, where a Termux sqlite3 package would win and fail this for no reason.
    t_has "/system/bin/sqlite3 is the module's wrapper" "sqlite3.real" "$(cat /system/bin/sqlite3 2>/dev/null)"
    for f in sqlite3 sqlite3.real sqldiff sqlite3-tool sqlite3-doctor; do
        P=$(stat -c '%a' "/system/bin/$f" 2>/dev/null)
        t_eq "/system/bin/$f mode 755" "755" "$P"
    done
    CTX=$(ls -Z /system/bin/sqlite3.real 2>/dev/null | awk '{print $1}')
    t_has "SELinux context of sqlite3.real" "system_file" "$CTX"
    OUT=$("$WRAP" -init /data/local/.sqliterc-full :memory: 'SELECT 42;' 2>&1)
    t_eq "-init .sqliterc-full is silent" "42" "$OUT"
    # A real system database, read-only: proves permissions + busy timeout.
    # Since Android 7 these providers keep their databases in device-encrypted
    # storage (/data/user_de/0); settings.db no longer exists at all (XML).
    LIVE=""
    for d in /data/user_de/0/com.android.providers.telephony/databases/telephony.db \
             /data/user_de/0/com.android.providers.telephony/databases/mmssms.db \
             /data/data/com.android.providers.contacts/databases/contacts2.db \
             /data/data/com.android.providers.telephony/databases/telephony.db; do
        [ -f "$d" ] && { LIVE="$d"; break; }
    done
    if [ -n "$LIVE" ]; then
        t_eq "reads a live system db: ${LIVE##*/}" "ok" "$("$WRAP" -readonly "$LIVE" 'PRAGMA quick_check;' 2>&1)"
    else
        skip "no known system database found to read"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    printf 'sqlite3-module-test v%s — %s\n' "$SUITE_VERSION" "$(date)"
    printf 'BIN_DIR: %s\nWORK:    %s\nkernel:  %s\n' "$BIN_DIR" "$WORK" "$(uname -rm)"
    [ -n "$(getprop ro.product.model 2>/dev/null)" ] && \
        printf 'device:  %s (Android %s)\n' "$(getprop ro.product.model)" "$(getprop ro.build.version.release)"

    test_files || return 0
    test_compile_options
    test_defaults
    test_features
    test_heavy
    test_wrapper
    test_sqldiff
    test_tool
    test_doctor
    test_module
}

rm -rf "$WORK"
mkdir -p "$WORK" || { echo "cannot create $WORK" >&2; exit 1; }
: > "$RESULTS"

main 2>&1 | tee "$LOG"

P=$(grep -c PASS "$RESULTS"); F=$(grep -c FAIL "$RESULTS"); S=$(grep -c SKIP "$RESULTS")
{
    printf '\n========================================\n'
    printf '  %s passed, %s failed, %s skipped\n' "$P" "$F" "$S"
    printf '========================================\n'
    printf 'Log: %s\n' "$LOG"
} | tee -a "$LOG"

[ "${KEEP:-0}" = "1" ] || rm -rf "$WORK"
[ "$F" -eq 0 ]
