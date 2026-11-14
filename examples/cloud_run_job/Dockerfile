# Builds the job as a native (AOT) binary on a minimal image.
#
# The build context is the repository root, because the example depends on the
# packages of this repository by path:
#
#   docker build -f examples/cloud_run_job/Dockerfile -t order-report-job .
#
# Dockerfile.dockerignore (next to this file) keeps the tests, build outputs
# and other packages out of the context; BuildKit (the default builder of
# current Docker) reads it.

# The Dart SDK that the example was tested with (3.12.2), pinned by digest.
FROM dart:3.12.2@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS build

WORKDIR /src
COPY cloud_firestore/cloud_firestore_dart/ cloud_firestore/cloud_firestore_dart/
COPY firebase_core/firebase_app_dart/ firebase_core/firebase_app_dart/
COPY firebase_auth/firebase_auth_providers_dart/ firebase_auth/firebase_auth_providers_dart/
COPY examples/cloud_run_job/ examples/cloud_run_job/

WORKDIR /src/examples/cloud_run_job
# The versions of pubspec.lock, not newer ones.
RUN dart pub get --enforce-lockfile
RUN dart compile exe bin/job.dart -o /src/job

# /runtime of the dart image holds what an AOT binary needs on an empty image:
# the C library, the DNS resolver, and the CA certificates for TLS to
# firestore.googleapis.com.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /src/job /app/job

# No credentials in the image: on Cloud Run the job gets the access token of
# its service account from the metadata server. Configure it with environment
# variables (FIREBASE_PROJECT_ID, ORDERS_COLLECTION, ...; see README.md).
ENTRYPOINT ["/app/job"]
