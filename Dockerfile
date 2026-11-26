# syntax=docker/dockerfile:1

# The Elm app: compiled, minified, and put together with its page and fonts.
# Not the slim image: the Elm compiler fetches packages over HTTPS and needs
# the system's CA certificates, which the slim image leaves out.
FROM node:22-bookworm AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# The Kotlin service, as a runnable distribution.
FROM eclipse-temurin:25-jdk AS backend
WORKDIR /build/backend
COPY backend/ ./
RUN --mount=type=cache,target=/root/.gradle ./gradlew --no-daemon :app:installDist

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
