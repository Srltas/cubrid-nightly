package org.testcontainers.cubrid;

import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.ImageNameSubstitutor;

/**
 * Runs the suite against the develop nightly image instead of the release image.
 *
 * <p>Every {@code cubrid/cubrid} reference is redirected, whatever tag it asks for,
 * so the {@code jdbc:tc:cubrid:<tag>://} URLs are covered too. Substitution happens
 * when the image is resolved, after {@code assertCompatibleWith} has already seen
 * the original name, so no production code has to change.
 *
 * <p>Override the target with {@code -Dcubrid.nightly.image=<ref>} to pin one build.
 */
public class NightlyImageSubstitutor extends ImageNameSubstitutor {

    private static final String RELEASE_REPO = "cubrid/cubrid";
    private static final String DEFAULT_NIGHTLY = "ghcr.io/srltas/cubrid-nightly:nightly";

    @Override
    public DockerImageName apply(DockerImageName original) {
        if (!RELEASE_REPO.equals(original.getUnversionedPart())) {
            return original;
        }
        String target = System.getProperty("cubrid.nightly.image", DEFAULT_NIGHTLY);
        return DockerImageName.parse(target).asCompatibleSubstituteFor(RELEASE_REPO);
    }

    @Override
    protected String getDescription() {
        return "CUBRID develop nightly substitutor";
    }
}
