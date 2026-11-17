# The image of tool/linux/run_in_container.sh: the Dart SDK (Debian), Java 21 for the Firestore emulator JAR, and
# SQLite. iproute2 is for the connectivity test that adds a network interface.
#
# libsqlite3-dev provides libsqlite3.so, the name sqlite3 2.x loads: cloud_firestore_dart's pubspec.lock stays on
# sqlite3 2.9.4 (see tool/build_web_test_assets.sh) and its tests no longer override the lookup with
# package:sqlite3/open.dart, which 3.x removed. With sqlite3 3.x the library comes from its build hook instead.
ARG DART_IMAGE=dart:stable
FROM eclipse-temurin:21-jre AS jre
FROM ${DART_IMAGE}
COPY --from=jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk PATH=/opt/java/openjdk/bin:/usr/lib/dart/bin:$PATH
RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-0 libsqlite3-dev curl iproute2 procps ca-certificates \
  && rm -rf /var/lib/apt/lists/*
