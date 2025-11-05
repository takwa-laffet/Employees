pipeline {
    agent any

    environment {
        SONAR_HOST = "http://192.168.13.8:9000"
        EMAIL_TO = "takwa.laffet@esprit.tn"
        GIT_URL = "https://github.com/takwa-laffet/Employees.git"
        GIT_BRANCH = "main"
        SONAR_PROJECT_KEY = "Employees"
        APP_IMAGE = "employees-app:latest"
        APP_URL = "http://localhost:8080"
        REPORT_DIR = "reports"
    }

    triggers {
        // Every minute (or replace with GitHub hook if you configure webhook)
        pollSCM('* * * * *')
    }

    tools {
        maven 'Maven'
        jdk 'JDK17'
    }

    stages {

        stage('Checkout Code') {
            steps {
                echo "📦 Checking out source..."
                git branch: "${GIT_BRANCH}", url: "${GIT_URL}", credentialsId: 'git-token'
            }
        }

        stage('Build Project') {
            steps {
                echo "🏗️ Building project..."
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', onlyIfSuccessful: true
            }
        }

        stage('Unit Tests & Coverage') {
            steps {
                echo "🧪 Running unit tests..."
                sh 'mvn test jacoco:report'
                archiveArtifacts artifacts: 'target/site/jacoco/**/*', allowEmptyArchive: true
            }
        }

        stage('Docker Build') {
            steps {
                echo "🐳 Building Docker image..."
                sh """
                    docker build -t ${APP_IMAGE} .
                    docker save ${APP_IMAGE} -o ${APP_IMAGE}.tar
                """
                archiveArtifacts artifacts: "${APP_IMAGE}.tar", onlyIfSuccessful: true
            }
        }

        stage('Security Scan - Docker Image (Trivy)') {
            steps {
                echo "🔐 Scanning Docker image with Trivy..."
                sh """
                    mkdir -p ${REPORT_DIR}
                    trivy image ${APP_IMAGE} \
                        --exit-code 0 \
                        --format html \
                        --output \${REPORT_DIR}/trivy-docker.html
                    zip \${REPORT_DIR}/trivy-docker.zip \${REPORT_DIR}/trivy-docker.html
                """
                archiveArtifacts artifacts: "${REPORT_DIR}/trivy-docker.zip", onlyIfSuccessful: true
            }
        }

        stage('Security Scan - Nikto') {
            steps {
                echo "🌐 Running Nikto web vulnerability scan..."
                sh """
                    docker run -d -p 8080:8080 ${APP_IMAGE}
                    sleep 20
                    mkdir -p ${REPORT_DIR}
                    nikto -h ${APP_URL} -o \${REPORT_DIR}/nikto.html -Format htm || true
                    zip \${REPORT_DIR}/nikto.zip \${REPORT_DIR}/nikto.html
                    docker stop \$(docker ps -q --filter ancestor=${APP_IMAGE})
                """
                archiveArtifacts artifacts: "${REPORT_DIR}/nikto.zip", onlyIfSuccessful: true
            }
        }

        stage('Security Scan - OWASP ZAP') {
            steps {
                echo "🕷️ Running OWASP ZAP scan..."
                sh """
                    mkdir -p ${REPORT_DIR}
                    docker run --rm -v \$(pwd):/zap/wrk:rw ghcr.io/zaproxy/zaproxy:stable \
                        zap-baseline.py -t ${APP_URL} -r \${REPORT_DIR}/zap.html || true
                    zip \${REPORT_DIR}/zap.zip \${REPORT_DIR}/zap.html
                """
                archiveArtifacts artifacts: "${REPORT_DIR}/zap.zip", onlyIfSuccessful: true
            }
        }

        stage('SAST - SonarQube') {
            steps {
                echo "🔎 Running SonarQube static analysis..."
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh """mvn sonar:sonar \
                        -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                        -Dsonar.host.url=${SONAR_HOST} \
                        -Dsonar.login=\$SONAR_TOKEN"""
                }
            }
        }

        stage('Documentation & Sensibilisation') {
            steps {
                echo "📝 Generating security and CI/CD documentation..."
                sh """
                    mkdir -p ${REPORT_DIR}
                    cat > \${REPORT_DIR}/pipeline-report.md <<EOF
# CI/CD DevSecOps Pipeline Report

## 🔧 Build Information
- Project: ${SONAR_PROJECT_KEY}
- Build Number: ${BUILD_NUMBER}
- Date: \$(date)

## ⚙️ Steps Executed
1. Checkout Code
2. Maven Build & Tests
3. Docker Image Build
4. Vulnerability Scans:
   - Trivy (File & Image)
   - Nikto (Web App)
   - OWASP ZAP (Dynamic)
   - SonarQube (SAST)

## 📊 Results
All reports are archived as build artifacts:
- Trivy: trivy-docker.html
- Nikto: nikto.html
- ZAP: zap.html
- SonarQube dashboard: ${SONAR_HOST}/dashboard?id=${SONAR_PROJECT_KEY}

## 🧠 Awareness
This CI/CD pipeline enforces security best practices:
- Code quality verification
- Automated vulnerability detection
- Continuous delivery readiness
EOF
                    zip \${REPORT_DIR}/pipeline-report.zip \${REPORT_DIR}/pipeline-report.md
                """
                archiveArtifacts artifacts: "${REPORT_DIR}/pipeline-report.zip"
            }
        }
    }

    post {
        success {
            emailext(
                subject: "✅ SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """<html>
                    <body>
                        <h2>🎉 Build Success</h2>
                        <p>All reports generated successfully.</p>
                        <ul>
                            <li><a href="${BUILD_URL}artifact/reports/pipeline-report.zip">📘 Full Documentation Report</a></li>
                            <li><a href="${BUILD_URL}artifact/reports/trivy-docker.zip">🐳 Docker Scan Report</a></li>
                            <li><a href="${BUILD_URL}artifact/reports/nikto.zip">🌐 Nikto Scan Report</a></li>
                            <li><a href="${BUILD_URL}artifact/reports/zap.zip">🕷️ OWASP ZAP Report</a></li>
                        </ul>
                    </body>
                </html>""",
                to: "${EMAIL_TO}",
                mimeType: 'text/html'
            )
        }
        failure {
            emailext(
                subject: "❌ FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """<html><body>
                        <p>❌ Build failed. Check logs: <a href="${BUILD_URL}">${BUILD_URL}</a></p>
                </body></html>""",
                to: "${EMAIL_TO}",
                mimeType: 'text/html'
            )
        }
    }
}
