#!/system/bin/sh
# SQLite3 Android Arm64 — uninstall cleanup
# Removes files deployed outside the module directory.
# system/bin/* is unmounted automatically by Magisk/KSU.

rm -f /data/local/.sqliterc-full

# sqlite3-tool writes a backup to "<destination>.sqlite3-tool-<pid>.tmp" and
# removes it itself; these only exist if it was killed mid-backup. Neither tool
# ever wrote to /data/local/tmp, which the old cleanup tried to clear.
rm -f /sdcard/*.sqlite3-tool-*.tmp /sdcard/Download/*.sqlite3-tool-*.tmp 2>/dev/null
exit 0
