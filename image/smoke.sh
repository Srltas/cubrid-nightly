#!/bin/bash
# Smoke test for a nightly image. Exits non-zero if the image cannot serve.
#
#   smoke.sh <image> <build_id>
#
# Lives next to the Dockerfile because what has to be checked changes with the
# image, not with the pipeline.
set -euo pipefail

IMAGE=${1:?usage: smoke.sh <image> <build_id>}
BUILD_ID=${2:?usage: smoke.sh <image> <build_id>}

NAME=nightly-smoke-$$
PORT=33099
WORKDIR=$(mktemp -d)
# -v also drops the anonymous volume the image's VOLUME line creates per run.
trap 'docker rm -f -v "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORKDIR"' EXIT

step() { printf '\n--- %s\n' "$1"; }
fail() { printf '\nFAILED: %s\n' "$1"; docker logs "$NAME" 2>&1 | tail -60; exit 1; }

wait_healthy() {
  local health=unset
  for _ in $(seq 1 90); do
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$NAME")
    [ "$health" = healthy ] && return 0
    [ "$health" = none ] && fail "image has no HEALTHCHECK, so readiness cannot be judged"
    [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = true ] || fail "container exited: $1"
    sleep 2
  done
  fail "not healthy after 180s during $1 (status: $health)"
}

step "start container"
docker run -d --name "$NAME" -p "$PORT:33000" "$IMAGE" >/dev/null

step "wait for HEALTHCHECK"
wait_healthy startup

step "engine is $BUILD_ID"
docker exec "$NAME" cubrid_rel | grep -qF "($BUILD_ID)" || fail "cubrid_rel does not report ($BUILD_ID)"

step "query over csql"
docker exec "$NAME" csql -u dba -c "SELECT 1" cubdb >/dev/null || fail "csql query failed"

step "query over jdbc, using the driver shipped in the image"
# The versioned jar carries the driver's own version, not the engine version, so
# go through the stable symlink. docker cp copies a symlink as a symlink, so
# resolve it inside the container first.
jar=$(docker exec "$NAME" readlink -f /home/cubrid/CUBRID/jdbc/cubrid_jdbc.jar | tr -d '\r')
docker cp "$NAME:$jar" "$WORKDIR/cubrid-jdbc.jar" >/dev/null
cat > "$WORKDIR/Smoke.java" <<'JAVA'
import java.sql.*;

public class Smoke {
  public static void main(String[] args) throws Exception {
    String url = "jdbc:cubrid:127.0.0.1:" + args[0] + ":cubdb:::";
    try (Connection c = DriverManager.getConnection(url, "dba", "");
         Statement s = c.createStatement()) {
      try (ResultSet r = s.executeQuery("SELECT 1")) {
        if (!r.next() || r.getInt(1) != 1) throw new IllegalStateException("unexpected result");
      }
      s.execute("CREATE TABLE t_smoke(id INT PRIMARY KEY, note VARCHAR(50))");
      s.execute("INSERT INTO t_smoke VALUES(1, 'smoke')");
      try (ResultSet r = s.executeQuery("SELECT note FROM t_smoke WHERE id = 1")) {
        if (!r.next() || !"smoke".equals(r.getString(1))) throw new IllegalStateException("round trip failed");
      }
      DatabaseMetaData m = c.getMetaData();
      System.out.println("server=" + m.getDatabaseProductVersion() + " driver=" + m.getDriverVersion());
    }
  }
}
JAVA
java -cp "$WORKDIR/cubrid-jdbc.jar" "$WORKDIR/Smoke.java" "$PORT" || fail "jdbc query failed"

step "restart keeps the data written above"
docker restart "$NAME" >/dev/null
wait_healthy restart
# Assert the row itself rather than a startup log line: this is the property that
# matters, and it does not depend on an engine message staying in English.
docker exec "$NAME" csql -u dba -c "SELECT note FROM t_smoke WHERE id = 1" cubdb 2>&1 \
  | grep -qF "'smoke'" || fail "the row written before the restart is gone"
docker exec "$NAME" csql -u dba -c "DROP TABLE t_smoke" cubdb >/dev/null || fail "cleanup failed"

printf '\nsmoke ok: %s\n' "$IMAGE"
