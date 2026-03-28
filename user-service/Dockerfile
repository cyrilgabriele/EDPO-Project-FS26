# ──────────────────────────────────────────────────
# Stage 1 – Build (Maven + Temurin JDK 21)
# ──────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21-alpine AS build

WORKDIR /workspace

# Copy parent + module POMs for dependency layer caching
COPY pom.xml .
COPY shared-events/pom.xml shared-events/
COPY market-data-service/pom.xml market-data-service/
COPY portfolio-service/pom.xml portfolio-service/
COPY transaction-service/pom.xml transaction-service/
COPY user-service/pom.xml user-service/
COPY onboarding-service/pom.xml onboarding-service/

# Pre-download dependencies for faster rebuilds
RUN mvn dependency:go-offline -pl user-service,shared-events -am -q

# Copy the actual sources
COPY shared-events/src shared-events/src
COPY user-service/src user-service/src

# Build the executable jar without running tests
RUN mvn package -pl user-service -am -DskipTests -q

# ──────────────────────────────────────────────────
# Stage 2 – Runtime (Temurin JRE 21)
# ──────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

COPY --from=build /workspace/user-service/target/*.jar app.jar

EXPOSE 8084

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD wget -qO- http://localhost:8084/actuator/health 2>/dev/null | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
