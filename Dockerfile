# ===== Stage 1: Build the application =====
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /app

# Copy pom and dependencies first
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy the rest of the code
COPY src ./src

# Build the jar file
RUN mvn clean package -DskipTests

# ===== Stage 2: Run the application =====
FROM eclipse-temurin:17-jdk-alpine
WORKDIR /app

# Copy the built jar from previous stage
COPY --from=build /app/target/*.jar app.jar

# Expose backend port
EXPOSE 8080

# Run app
ENTRYPOINT ["java","-jar","app.jar"]
