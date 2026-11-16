#!/system/bin/sh
# service.sh - runs late in boot, so waiting here is safe.

# ${0%/*} is the module directory only when the script is called with a path,
# which is how Magisk/KSU start it. Fall back to "." so a manual "sh
# service.sh" from inside the module still works.
MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
SQLITE_REAL="$MODDIR/system/bin/sqlite3.real"
PROP="$MODDIR/module.prop"
SQLITERC_DIR="/data/local"
FALLBACK_DESC="Max-feature standalone SQLite build for Android Arm64, with sqldiff, sqlite3-tool and sqlite3-doctor"

# Wait for the binary to become visible (up to 10 s on a slow mount).
i=0
while [ ! -f "$SQLITE_REAL" ] && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done

# ── Determine status ──────────────────────────────────────────────────────────
if [ ! -f "$SQLITE_REAL" ]; then
    STATUS="binary missing"
elif VER=$("$SQLITE_REAL" --version 2>/dev/null | cut -d' ' -f1) && [ -n "$VER" ]; then
    STATUS="v$VER working"
    # Surface a build mistake instead of hiding it. SQLITE_SECURE_DELETE is an
    # #ifdef flag, so -DSQLITE_SECURE_DELETE=0 turns it ON and slows every
    # DELETE and VACUUM down.
    if "$SQLITE_REAL" ":memory:" "PRAGMA compile_options;" 2>/dev/null |
        grep -qx "SECURE_DELETE"; then
        STATUS="$STATUS, secure_delete ON"
    fi
else
    STATUS="not working"
fi

# ── Update module.prop ────────────────────────────────────────────────────────
# Rebuilt with a read loop rather than sed -i: nothing in the description can
# then be mistaken for a sed replacement pattern, and the file is only touched
# when the text actually changes.
# The base text comes from module.prop itself, minus the status this script
# appended on an earlier boot, so a description changed in module.prop is no
# longer overwritten by a copy kept here. Only the known status forms are
# cut, so a description that happens to end in "(...)" stays whole.
CUR_DESC=$(grep '^description=' "$PROP" 2>/dev/null | head -n 1)
BASE_DESC="${CUR_DESC#description=}"
case "$BASE_DESC" in
    # The literal parts are quoted: unquoted "(" after a space is not taken
    # literally by mksh inside ${var%pattern}, and nothing was cut.
    *" (v"*" working"*")") BASE_DESC="${BASE_DESC%" (v"*" working"*")"}" ;;
    *" (binary missing)")  BASE_DESC="${BASE_DESC%" (binary missing)"}" ;;
    *" (not working)")     BASE_DESC="${BASE_DESC%" (not working)"}" ;;
esac
[ -n "$BASE_DESC" ] || BASE_DESC="$FALLBACK_DESC"
NEW_DESC="description=$BASE_DESC ($STATUS)"

if [ "$NEW_DESC" != "$CUR_DESC" ] && [ -f "$PROP" ]; then
    TMP="$PROP.tmp.$$"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            description=*) printf '%s\n' "$NEW_DESC" ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$PROP" > "$TMP" 2>/dev/null
    [ -s "$TMP" ] && mv -f "$TMP" "$PROP" || rm -f "$TMP"
fi

# ── Deploy the reference .sqliterc ────────────────────────────────────────────
if [ -f "$MODDIR/files/sqliterc-full" ]; then
    cp -f "$MODDIR/files/sqliterc-full" "$SQLITERC_DIR/.sqliterc-full" 2>/dev/null
    chmod 644 "$SQLITERC_DIR/.sqliterc-full" 2>/dev/null
fi

exit 0
