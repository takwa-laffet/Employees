# Use OpenJDK 17
FROM openjdk:17-jdk-slim

# Copy project JAR
COPY target/employee-directory-1.0.0.jar app.jar

# Expose port
EXPOSE 8080

# Run app
ENTRYPOINT ["java", "-jar", "app.jar"]
