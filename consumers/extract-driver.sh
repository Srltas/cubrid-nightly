#!/bin/bash
# Extract the JDBC driver that ships inside a nightly image.
#
#   extract-driver.sh <image> <output dir>
#
# Prints the driver version on stdout, so a caller can do:
#   VER=$(extract-driver.sh "$IMAGE" /tmp/drv)
#
# The container is never started. The whole jdbc directory is copied rather
# than the single jar, because docker cp copies a symlink as a symlink and
# cubrid_jdbc.jar is one; taking the directory brings its target along.
set -euo pipefail

IMAGE=${1:?usage: extract-driver.sh <image> <output dir>}
OUT=${2:?usage: extract-driver.sh <image> <output dir>}

mkdir -p "$OUT"
cid=$(docker create "$IMAGE")
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker cp "$cid:/home/cubrid/CUBRID/jdbc/." "$OUT/" >/dev/null

# flatDir matches on the file name, so leave exactly one cubrid-jdbc-*.jar.
rm -f "$OUT"/*-sources.jar "$OUT"/*-javadoc.jar "$OUT"/cubrid_jdbc.jar

jar=$(ls "$OUT"/cubrid-jdbc-*.jar)
[ "$(printf '%s\n' "$jar" | wc -l)" -eq 1 ] || { echo "expected one jar, found:" >&2; echo "$jar" >&2; exit 1; }
basename "$jar" .jar | sed 's/^cubrid-jdbc-//'
