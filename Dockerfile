# Multi-stage Dockerfile para videoclub-gateway (Java 25 + Spring Boot 4.1.1 + Spring Cloud Gateway 5)
#
# Cinco etapas con responsabilidades distintas:
#  - dev            : solo dependencias de Maven. A proposito no copia src/ ni define
#                     CMD: el codigo y el comando se inyectan desde docker-compose.yml
#                     (bind mount + command: mvn spring-boot:run).
#  - build          : hereda de dev y compila el .jar. Con `FROM dev AS build` se
#                     reutiliza la capa de dependencias en cache.
#  - runtime        : imagen productiva JVM (Alpine JRE 25, no-root, HEALTHCHECK).
#  - native-build   : compila un binario nativo con GraalVM + AOT de Spring Boot.
#  - native-runtime : imagen productiva nativa (Debian slim, no-root, HEALTHCHECK).
#
# Las dos ultimas son OPCIONALES y no participan del build por defecto.
# Se eligen con `--target native-runtime` (ver docker-compose.prod.yml).

# ---- Etapa dev (docker-compose, hot-reload) ----
FROM maven:3.9-eclipse-temurin-25 AS dev
WORKDIR /app
COPY pom.xml ./
RUN mvn dependency:go-offline

# ---- Etapa build ----
FROM dev AS build
COPY src ./src
RUN mvn clean package -DskipTests

# ---- Etapa runtime ----
FROM eclipse-temurin:25-jre-alpine AS runtime
WORKDIR /app

LABEL org.opencontainers.image.title="videoclub-gateway" \
      org.opencontainers.image.description="Spring Cloud Gateway for VideoClub" \
      org.opencontainers.image.authors="VideoClub UNRN"

RUN apk add --no-cache curl
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /app/target/*.jar app.jar
USER app

ENV PORT=9500
EXPOSE ${PORT}

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
    CMD curl -f http://localhost:${PORT}/actuator/health || exit 1

CMD ["java", "-jar", "app.jar"]

# ---- Etapa native-build ----
FROM ghcr.io/graalvm/native-image-community:25 AS native-build
WORKDIR /app

# Wrapper + pom primero: capa de dependencias cacheable, igual que en la etapa dev.
COPY .mvn ./.mvn
COPY mvnw pom.xml ./
RUN ./mvnw -B -Pnative dependency:go-offline

COPY src ./src

RUN ./mvnw -B -Pnative clean package -DskipTests
RUN ./mvnw -B -Pnative native:compile-no-fork -DskipTests

# ---- Etapa native-runtime ----
FROM debian:bookworm-slim AS native-runtime
WORKDIR /app

LABEL org.opencontainers.image.title="videoclub-gateway-native" \
      org.opencontainers.image.description="Spring Cloud Gateway for VideoClub (GraalVM native image)" \
      org.opencontainers.image.authors="VideoClub UNRN"

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system app && useradd --system --gid app app
COPY --from=native-build /app/target/videoclub-gateway ./videoclub-gateway
USER app

ENV PORT=9500
EXPOSE ${PORT}

# start-period corto: el binario nativo arranca en milisegundos, no en segundos.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=5s \
    CMD curl -f http://localhost:${PORT}/actuator/health || exit 1

ENTRYPOINT ["./videoclub-gateway"]
