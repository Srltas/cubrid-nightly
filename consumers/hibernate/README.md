# Hibernate ORM against a nightly build

Runs the Hibernate suite with both the engine and the JDBC driver taken from
the same nightly image. **No file in hibernate-orm changes.**

```bash
IMAGE=ghcr.io/srltas/cubrid-nightly:nightly
DRV=/tmp/cubrid-nightly-driver
VER=$(/path/to/cubrid-nightly/consumers/extract-driver.sh "$IMAGE" "$DRV")

cd /path/to/hibernate-orm
CUBRID_IMAGE=$IMAGE ./db.sh cubrid

ADDITIONAL_REPO=$DRV ./gradlew ciCheck -Pdb=cubrid \
  --init-script /path/to/cubrid-nightly/consumers/hibernate/cubrid-nightly-driver.init.gradle \
  -Dcubrid.driver.version="$VER"
```

## Why these two hooks

Both already exist upstream; neither was added for this.

`docker-compose/latest/cubrid/docker-compose.yaml` reads the image from an
environment variable, so `CUBRID_IMAGE` is enough to swap the engine:

```yaml
image: ${CUBRID_IMAGE:-docker.io/cubrid/cubrid:11.4@sha256:...}
```

`settings.gradle` adds a flatDir repository when `ADDITIONAL_REPO` is set, and
says why in its own comment:

```groovy
// Allow loading additional dependencies from a local path;
// useful to load JDBC drivers which can not be distributed in public.
```

The container is started by `db.sh` before Gradle runs, so there is room in
between to take the driver out of the image.

## Why an init script and not -P

`gradle/libs.versions.toml` pins a released driver, and the property override
route only works for versions listed in `settings.gradle`'s
`overrideableVersion` calls. cubrid is not one of them, so
`-Pgradle.libs.versions.cubrid` has no effect today. The init script rewrites
the requested version instead, which needs no change to hibernate-orm.

Adding one line to `settings.gradle` upstream would make the property route
work and would match the surrounding convention. The two are not exclusive.

## Verified

Against `hibernate-core` on 2026-09-10:

```
org.cubrid:cubrid-jdbc:11.3.2.0053 -> 11.4.0.0077
Selection reasons:
   - Selected by rule: driver taken from the nightly engine image

RESOLVED: .../cubrid-jdbc-11.4.0.0077.jar
```

Run with `--offline`, so the jar cannot have come from Maven Central. Without
`ADDITIONAL_REPO` the build fails with `Could not resolve
org.cubrid:cubrid-jdbc:11.4.0.0077` rather than quietly falling back to the
released driver, which is the behaviour that matters: a silent fallback would
mean testing the release driver while believing otherwise.
