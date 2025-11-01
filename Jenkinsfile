pipeline {
    agent any

    environment {
        // Sonar server URL
        SONAR_HOST = "http://192.168.13.2:9000"
        // Credential ID in Jenkins for Sonar token
        SONAR_CRED = "sonar-token"
        // Email addresses
        EMAIL_TO = "takwa5laffet@gmail.com"
    }

    options {
        timeout(time: 60, unit: 'MINUTES') // Abort if build takes longer than 60 min
        ansiColor('xterm') // Colored console output
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Checking out code from repository..."
                checkout scm
            }
        }

        stage('Build') {
            steps {
                echo "Building the Spring Boot project..."
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', onlyIfSuccessful: true
            }
        }

        stage('SAST - SonarQube Analysis') {
            environment {
                SONAR_TOKEN = credentials('sonar-token')
            }
            steps {
                echo "Running SonarQube analysis..."
                sh 'mvn sonar:sonar -Dsonar.host.url=${SONAR_HOST} -Dsonar.login=${SONAR_TOKEN}'
            }
        }

        stage('SCA - Dependency Check') {
            steps {
                echo "Running OWASP Dependency Check..."
                sh 'dependency-check --project Employees --scan . --format ALL -o dependency-check-report'

                script {
                    def xml = readFile('dependency-check-report/dependency-check-report.xml')
                    if (xml.contains('severity="Critical"') || xml.contains('severity="High"')) {
                        error "Dependency-Check found vulnerabilities of high or critical severity!"
                    }
                }

                archiveArtifacts artifacts: 'dependency-check-report/**', allowEmptyArchive: true
            }
        }

        stage('Docker Build & Scan (Trivy)') {
            steps {
                echo "Building Docker image..."
                sh 'docker build -t employees-app:${BUILD_NUMBER} .'

                echo "Scanning Docker image with Trivy..."
                sh '''
                    trivy image --exit-code 1 --severity HIGH,CRITICAL employees-app:${BUILD_NUMBER} || true
                    trivy image --format json -o trivy-report.json employees-app:${BUILD_NUMBER}
                '''

                script {
                    def json = readFile('trivy-report.json')
                    if (json.contains('"Severity":"CRITICAL"')) {
                        error "Trivy found critical vulnerabilities in Docker image!"
                    }
                }

                archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
            }
        }

        stage('Secrets Scan - Gitleaks') {
            steps {
                echo "Running Gitleaks scan..."
                sh 'gitleaks detect --source . --report-path=gitleaks-report.json || true'

                script {
                    def report = readFile('gitleaks-report.json')
                    if (report.contains('"leaks": [')) {
                        error "Gitleaks detected potential secrets!"
                    }
                }

                archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
            }
        }

        stage('DAST - OWASP ZAP Scan') {
            steps {
                echo "Running ZAP DAST scan..."
                sh '''
                    docker run --rm -v $(pwd):/zap/wrk/:rw owasp/zap2docker-stable \
                    zap-full-scan.py -t http://localhost:8080 -r zap-report.html || true
                '''

                script {
                    def report = readFile('zap-report.html')
                    if (report.contains("High")) {
                        error "ZAP scan found high-level issues!"
                    }
                }

                archiveArtifacts artifacts: 'zap-report.html', allowEmptyArchive: true
            }
        }
    }

    post {
        success {
            mail to: "${EMAIL_TO}",
                 subject: "✅ SUCCESS: ${JOB_NAME} #${BUILD_NUMBER}",
                 body: "The build succeeded. Reports are available in Jenkins."
        }

        unstable {
            mail to: "${EMAIL_TO}",
                 subject: "⚠️ UNSTABLE: ${JOB_NAME} #${BUILD_NUMBER}",
                 body: "The build is unstable. Check reports for details."
        }

        failure {
            mail to: "${EMAIL_TO}",
                 subject: "❌ FAILURE: ${JOB_NAME} #${BUILD_NUMBER}",
                 body: "The build failed. Please check reports in Jenkins."
        }

        always {
            archiveArtifacts artifacts: '**/target/*.jar, dependency-check-report/**, trivy-report.json, gitleaks-report.json, zap-report.html', allowEmptyArchive: true
        }
    }
}
