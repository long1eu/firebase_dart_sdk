# The image of tool/linux/run_in_container.sh: the Dart SDK (Debian), Java 21 for the Firestore emulator JAR, and the
# runtime package of SQLite only (libsqlite3-0, no -dev), as on a plain Linux machine. iproute2 is for the connectivity
# test that adds a network interface.
ARG DART_IMAGE=dart:stable
FROM eclipse-temurin:21-jre AS jre
FROM ${DART_IMAGE}
COPY --from=jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk PATH=/opt/java/openjdk/bin:/usr/lib/dart/bin:$PATH
RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-0 curl iproute2 procps ca-certificates \
  && rm -rf /var/lib/apt/lists/*
