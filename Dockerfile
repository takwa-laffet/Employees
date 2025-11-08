# ---- Stage 1: Dependencies ----
FROM maven:3.9.9-eclipse-temurin-21-slim AS deps
WORKDIR /app
COPY pom.xml .
# Download dependencies
RUN mvn dependency:go-offline -B

# ---- Stage 2: Build ----
FROM maven:3.9.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY . .
RUN mvn clean package -DskipTests


# ---- Stage 3: Security Scan ----
FROM aquasec/trivy:0.47.0 AS security-scan
COPY --from=builder /app/target/*.jar /app/app.jar
RUN trivy fs --severity HIGH,CRITICAL --no-progress /app

# ---- Stage 4: Run ----
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]


# Add non-root user
RUN addgroup --system --gid 1001 appuser && \
    adduser --system --uid 1001 --gid 1001 appuser

# Copy jar and switch to non-root user
COPY --from=builder --chown=appuser:appuser /app/target/*.jar app.jar

USER appuser
EXPOSE 8080

# Add health check
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Set JVM options for containers
ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
