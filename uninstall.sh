#!/system/bin/sh
# SQLite3 Android Arm64 — uninstall cleanup
# Removes files deployed outside the module directory.
# system/bin/* is unmounted automatically by Magisk/KSU.

rm -f /data/local/.sqliterc-full
rm -f /data/local/tmp/sqlite3-doctor-*.tmp
rm -f /data/local/tmp/sqlite3-tool-*.tmp
exit 0
