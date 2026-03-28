# ──────────────────────────────────────────────────
# Stage 1 – Build (Maven + JDK 21)
# ──────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21-alpine AS build

WORKDIR /workspace

# Copy parent and module POMs first so dependency layer is cached separately
COPY pom.xml .
COPY shared-events/pom.xml shared-events/
COPY market-data-service/pom.xml market-data-service/
COPY portfolio-service/pom.xml portfolio-service/
COPY transaction-service/pom.xml transaction-service/
COPY user-service/pom.xml user-service/
COPY onboarding-service/pom.xml onboarding-service/

# Pre-download dependencies (cached as a layer)
RUN mvn dependency:go-offline -pl portfolio-service,shared-events -am -q

# Copy source code
COPY shared-events/src shared-events/src
COPY portfolio-service/src portfolio-service/src

# Build the fat JAR
RUN mvn package -pl portfolio-service -am -DskipTests -q

# ──────────────────────────────────────────────────
# Stage 2 – Runtime (JRE 21 slim)
# ──────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

COPY --from=build /workspace/portfolio-service/target/*.jar app.jar

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO- http://localhost:8082/actuator/health 2>/dev/null | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
