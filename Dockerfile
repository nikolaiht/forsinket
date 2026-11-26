# syntax=docker/dockerfile:1

# The Elm app: compiled, minified, and put together with its page and fonts.
# Not the slim image: the Elm compiler fetches packages over HTTPS and needs
# the system's CA certificates, which the slim image leaves out.
#
# Everything that is downloaded is downloaded in layers of its own, which
# change when the list of dependencies does and not when the code does. The
# steps that build the code run without a network, so a build after a code
# change cannot fail because a package site is slow or says no.
FROM node:22-bookworm AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
# The Elm packages. The compiler fetches every package in elm.json before it
# compiles anything, so compiling a module with nothing in it is enough.
COPY frontend/elm.json ./
RUN mkdir src \
    && printf 'module Warmup exposing (warm)\n\n\nwarm : Int\nwarm =\n    0\n' > src/Warmup.elm \
    && npx elm make src/Warmup.elm --output=/dev/null \
    && rm -r src elm-stuff
COPY frontend/ ./
RUN --network=none npm run build

# The Kotlin service, as a runnable distribution.
FROM eclipse-temurin:25-jdk AS backend
WORKDIR /build/backend
# Gradle itself, its plugins and the libraries. One empty source file in each
# module makes the compiler run, so that it is fetched here as well.
COPY backend/gradlew backend/settings.gradle.kts backend/build.gradle.kts ./
COPY backend/gradle/ gradle/
COPY backend/domain/build.gradle.kts domain/
COPY backend/app/build.gradle.kts app/
RUN mkdir -p domain/src/main/kotlin app/src/main/kotlin \
    && echo 'package warmup' > domain/src/main/kotlin/Warmup.kt \
    && echo 'package warmup' > app/src/main/kotlin/Warmup.kt \
    && ./gradlew --no-daemon :app:installDist \
    && rm -r domain/src app/src domain/build app/build
COPY backend/ ./
RUN --network=none ./gradlew --no-daemon --offline :app:installDist

# What runs: a Java runtime, the service, and the built app for it to serve.
FROM eclipse-temurin:25-jre
RUN useradd --system --no-create-home forsinket
WORKDIR /app
COPY --from=backend /build/backend/app/build/install/app/ ./
COPY --from=frontend /build/frontend/dist/ ./web/
ENV PORT=8080 \
    WEB_ROOT=/app/web
EXPOSE 8080
USER forsinket
ENTRYPOINT ["/app/bin/app"]
