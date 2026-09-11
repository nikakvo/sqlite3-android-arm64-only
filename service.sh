#!/system/bin/sh
# service.sh — runs late in boot, so waiting here is safe.

MODDIR=${0%/*}
SQLITE_REAL="$MODDIR/system/bin/sqlite3.real"
PROP="$MODDIR/module.prop"
SQLITERC_DIR="/data/local"
BASE_DESC="Max-feature standalone SQLite build for Android Arm64, with sqldiff, sqlite3-tool and sqlite3-doctor"

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
        STATUS="$STATUS (secure_delete ON)"
    fi
else
    STATUS="not working"
fi

# ── Update module.prop ────────────────────────────────────────────────────────
# Rebuilt with a read loop rather than sed -i: nothing in the description can
# then be mistaken for a sed replacement pattern, and the file is only touched
# when the text actually changes.
NEW_DESC="description=$BASE_DESC ($STATUS)"
CUR_DESC=$(grep '^description=' "$PROP" 2>/dev/null)

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
