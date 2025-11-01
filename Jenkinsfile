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
        // Abort if build takes longer than 60 min
        timeout(time: 60, unit: 'MINUTES')
        // Show colored console output
        ansiColor('xterm')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                // Build project without running tests (or you can run tests if you want)
                sh "mvn clean package -DskipTests"
                archiveArtifacts artifacts: 'target/*.jar', onlyIfSuccessful: true
            }
        }

        stage('SAST - SonarQube Analysis') {
            environment {
                SONAR_TOKEN = credentials("${env.SONAR_CRED}")
            }
            steps {
                echo "Running SonarQube analysis..."
                sh "mvn sonar:sonar -Dsonar.host.url=${env.SONAR_HOST} -Dsonar.login=${SONAR_TOKEN}"
            }
            post {
                always {
                    // Optionally download quality gate status, or fail if quality gate fails
                    // This part can be improved using SonarQube Jenkins plugin or webhook
                }
            }
        }

        stage('SCA - Dependency-Check') {
            steps {
                echo "Running OWASP Dependency-Check..."
                sh "dependency-check --project Employees --scan . --format ALL -out dependency-check-report"

                script {
                    // Simple rule: fail if any “Critical” severity in the XML report
                    def xml = readFile('dependency-check-report/dependency-check-report.xml')
                    if (xml.contains('severity="Critical"') || xml.contains('severity="High"')) {
                        error "Dependency-Check found vulnerabilities of high or critical severity"
                    }
                }

                archiveArtifacts artifacts: 'dependency-check-report/**', allowEmptyArchive: true
            }
        }

        stage('Docker Build & Scan (Trivy)') {
            steps {
                echo "Building Docker image..."
                sh "docker build -t employees-app:${env.BUILD_NUMBER} ."

                echo "Scanning Docker image with Trivy..."
                // exit-code 1 if vulnerabilities found in severities HIGH or CRITICAL
                sh """
                    trivy image --exit-code 1 --severity HIGH,CRITICAL employees-app:${env.BUILD_NUMBER} || true
                    trivy image --format json -o trivy-report.json employees-app:${env.BUILD_NUMBER}
                """

                script {
                    def json = readFile('trivy-report.json')
                    if (json.contains('"Vulnerabilities":') && json.contains('"Severity":"CRITICAL"') ) {
                        error "Trivy found critical vulnerabilities in the Docker image"
                    }
                }

                archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
            }
        }

        stage('Secrets Scan - Gitleaks') {
            steps {
                echo "Running Gitleaks to detect secrets..."
                sh "gitleaks detect --source . --report-path=gitleaks-report.json || true"

                script {
                    def greport = readFile('gitleaks-report.json')
                    if (grep(greport, /\"leaks\": \[/)) {
                        error "Gitleaks detected potential secrets in repository"
                    }
                }

                archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
            }
        }

        stage('DAST - OWASP ZAP Scan') {
            steps {
                echo "Running ZAP DAST scan..."
                // Adjust the target URL to the running app (e.g. Jenkins or local server inside VM)
                sh """
                  docker run --rm -v $(pwd):/zap/wrk/:rw owasp/zap2docker-stable zap-full-scan.py -t http://localhost:8080 -r zap-report.html || true
                """

                script {
                    def report = readFile('zap-report.html')
                    if (report.contains("High")) {
                        error "ZAP scan found high-level issues"
                    }
                }

                archiveArtifacts artifacts: 'zap-report.html', allowEmptyArchive: true
            }
        }
    }

    post {
        success {
            mail to: "${env.EMAIL_TO}",
                 subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "The build succeeded. Reports are available in Jenkins."
        }
        unstable {
            mail to: "${env.EMAIL_TO}",
                 subject: "UNSTABLE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "The build is unstable. Check the reports for details."
        }
        failure {
            mail to: "${env.EMAIL_TO}",
                 subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "The build failed. Please check the reports in Jenkins."
        }
        always {
            // Archive artifacts from all stages
            archiveArtifacts artifacts: '**/target/*.jar, dependency-check-report/**, trivy-report.json, gitleaks-report.json, zap-report.html', allowEmptyArchive: true
        }
    }
}
