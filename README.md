# cubrid-nightly

A container image of the CUBRID **development** engine, rebuilt twice a day, so
that JDBC, Testcontainers and Hibernate compatibility can be checked before a
release rather than after one.

Not a release. Not supported. Expected to break.

```bash
docker run -d -p 33000:33000 ghcr.io/srltas/cubrid-nightly:nightly
```

## Tags

| tag | meaning |
| --- | --- |
| `11.5.0.2552-aef5776` | one build, forever. Pushed even if its smoke test failed, so a broken build stays available for investigation. The name is the ftp directory name. |
| `nightly` | the newest build that PASSED the smoke test |
| `latest` | alias of `nightly` |

Which build a moving tag currently points at:

```bash
docker image inspect ghcr.io/srltas/cubrid-nightly:nightly \
  --format '{{index .Config.Labels "org.cubrid.nightly.build_id"}}'
```

## How it works

The engine is **not** rebuilt here. CUBRID's own build already publishes a
develop package to `ftp.cubrid.org/CUBRID_Engine/nightly/daily_build/` every
build day. This repository only packages it.

```
ftp.cubrid.org  ->  GitHub Actions  ->  ghcr.io/srltas/cubrid-nightly
 (already runs)     (this repo)          (public, anonymous pull)
```

Each run resolves the newest build, verifies it against the drop's `hash.md5`,
builds the image, smoke tests it, and publishes. Measured: about 4m30s when
there is a new build, about 10s when there is not.

A green run is silent, so only a definite answer is allowed to end a run
quietly. An unreachable registry, an unexpected ftp status, or an index whose
shape changed fails loudly instead of looking like a quiet day.

## Layout

| path | what |
| --- | --- |
| `.github/workflows/nightly-image.yml` | the pipeline |
| `image/` | Dockerfile, startup scripts, smoke test |
| `consumers/extract-driver.sh` | pull the JDBC driver out of an image |
| `consumers/hibernate/` | run the Hibernate suite against a nightly build |
| `consumers/testcontainers/` | run testcontainers-cubrid against a nightly build |
| `docs/` | design and verification write-ups, and their editable sources |

## Testing a driver, not just an engine

The image carries the JDBC driver built alongside its engine. Extracting it
means the engine and the driver under test come from **one build**, which is
the combination that will actually ship.

```bash
VER=$(consumers/extract-driver.sh ghcr.io/srltas/cubrid-nightly:nightly /tmp/drv)
```

See `consumers/hibernate/` and `consumers/testcontainers/` for how each suite
picks that jar up. Neither needs a change to the suite's own repository.

## Operating notes

- **The publishing repository needs write access on the package.** GHCR grants
  that automatically only to the repository that first published it, so a
  package published from somewhere else has to be granted access once, under
  the package's *Package settings -> Manage Actions access*. Without it the
  run gets through build and smoke test and then fails with
  `denied: permission_denied: write_package`.
- Retention keeps the 15 newest immutable versions. Whatever `nightly` and
  `latest` point at is excluded explicitly. Version rank is by first-publish
  time, which does not move when a tag is re-pointed, so a plain "keep N"
  policy would eventually delete the image `nightly` still points at.
- Scheduled workflows in a public repository stop after 60 days without
  repository activity, and the runs themselves do not count. Any commit here
  resets that clock.
- GitHub Actions minutes and public GHCR storage are free. Keeping this
  repository public is what makes that true.
- GitHub only indexes workflow files that appear in a push diff. Files pushed
  as part of `gh repo create --push` are not registered, and the workflow
  stays invisible to `gh workflow run` with no error anywhere. Touching the
  file and pushing again fixes it.
