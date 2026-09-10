# testcontainers-cubrid against a nightly build

`CubridContainer` checks that the image is `cubrid/cubrid`, so a different
image cannot simply be passed in. Testcontainers provides the intended hook:
an `ImageNameSubstitutor` swaps the image when it is resolved, after that
compatibility check has already seen the original name.

Copy both files into the suite's test sources:

```
NightlyImageSubstitutor.java -> src/test/java/org/testcontainers/cubrid/
testcontainers.properties    -> src/test/resources/
```

```bash
./gradlew cleanTest test
```

Pin one build instead of the moving tag:

```bash
./gradlew cleanTest test -Dcubrid.nightly.image=ghcr.io/srltas/cubrid-nightly:11.5.0.2552-aef5776
```

This covers the `jdbc:tc:cubrid:<tag>://` URLs too, which are otherwise tied to
the `CubridContainer.IMAGE` constant.

## Also swapping the driver

The suite resolves `org.cubrid:cubrid-jdbc` from Maven Central. To test the
driver from the same image, install the extracted jar into a job-local
repository and rewrite the version:

```bash
VER=$(../extract-driver.sh ghcr.io/srltas/cubrid-nightly:nightly /tmp/drv)
mvn -B install:install-file -Dmaven.repo.local=/tmp/m2 \
  -Dfile="/tmp/drv/cubrid-jdbc-$VER.jar" \
  -DgroupId=org.cubrid -DartifactId=cubrid-jdbc -Dversion="$VER" -Dpackaging=jar

./gradlew cleanTest test --init-script nightly-driver.init.gradle \
  -Dnightly.driver.repo=/tmp/m2 -Dnightly.driver.version="$VER"
```

## Verified

2026-09-10, all three combinations 9/9:

| combination | engine | driver | result |
| --- | --- | --- | --- |
| baseline | release 11.4 | 11.3.2.0053 | 9 / 9 |
| nightly engine | 11.5.0.2552 | 11.3.2.0053 | 9 / 9 |
| nightly engine and driver | 11.5.0.2552 | 11.4.0.0077 | 9 / 9 |

Note what this suite is: nine tests about container lifecycle and HA. It
catches a driver that cannot connect. It does not catch a subtle type-handling
regression; Hibernate is where that shows up.
