pipeline {
    agent any

    environment {
        SONAR_HOST = "http://192.168.13.2:9000"
    }

    options {
        timeout(time: 60, unit: 'MINUTES')
        ansiColor('xterm')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Test') {
            steps {
                // run tests; adjust as needed
                sh './mvnw clean package -DskipTests=false'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true
                }
            }
        }

        stage('SAST - SonarQube Analysis') {
            environment {
                SONAR_TOKEN = credentials('sonar-token')   // make sure you set this in Jenkins credentials
            }
            steps {
                echo "Running SonarQube analysis..."
                sh "./mvnw sonar:sonar -Dsonar.host.url=${env.SONAR_HOST} -Dsonar.login=${SONAR_TOKEN}"
            }
        }

        stage('SCA - Dependency Check') {
            steps {
                echo "Running Dependency-Check SCA..."
                sh "dependency-check --project studentsfoyer --scan . --format ALL -out dependency-check-report"
                script {
                    def xml = readFile('dependency-check-report/dependency-check-report.xml')
                    if (xml.contains("severity=\"Critical\"") || xml.contains("severity=\"High\"")) {
                        error "Dependency-Check found high or critical vulnerabilities"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'dependency-check-report/**', allowEmptyArchive: true
                }
            }
        }

        stage('Docker Build & Trivy Scan') {
            steps {
                echo "Building Docker image..."
                sh "docker build -t studentsfoyer-app:${env.BUILD_NUMBER} ."

                echo "Scanning Docker image with Trivy..."
                // Exit code 1 if vulnerabilities found in HIGH/CRITICAL
                sh """
                  trivy image --exit-code 1 --severity HIGH,CRITICAL studentsfoyer-app:${env.BUILD_NUMBER} || true
                  trivy image --format json -o trivy-report.json studentsfoyer-app:${env.BUILD_NUMBER}
                """

                script {
                    def out = sh(script: "jq '.Results[].Vulnerabilities | length' trivy-report.json || echo 0", returnStdout: true).trim()
                    if (out != '' && out != '0') {
                        error "Trivy detected critical/high vulnerabilities"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Secrets Scan – Gitleaks') {
            steps {
                echo "Running Gitleaks secrets scan..."
                sh 'gitleaks detect --source . --report-path=gitleaks-report.json || true'
                script {
                    def leaks = sh(script: "jq '. | length' gitleaks-report.json || echo 0", returnStdout: true).trim()
                    if (leaks != '' && leaks != '0') {
                        error "Gitleaks found secrets in the repo"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('DAST – OWASP ZAP Scan') {
            steps {
                echo "Running OWASP ZAP dynamic scan..."
                // Adjust target URL (staging) as needed
                sh """
                   docker run --rm -v $(pwd):/zap/wrk/:rw owasp/zap2docker-stable zap-full-scan.py \
                     -t http://localhost:8080 -r zap-report.html || true
                """
                script {
                    def hasHigh = sh(script: "grep -i 'High' zap-report.html || true", returnStdout: true).trim()
                    if (hasHigh) {
                        error "ZAP found high risk issues"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'zap-report.html', allowEmptyArchive: true
                }
            }
        }
    }

    post {
        success {
            mail to: 'takwa5laffet@gmail.com',
                 subject: "Build Success: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "Congratulations! Build succeeded for studentsfoyer project."
        }
        failure {
            mail to: 'takwa5laffet@gmail.com',
                 subject: "Build Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "Build failed. Please check the details in Jenkins and the attached reports."
        }
        always {
            archiveArtifacts artifacts: '**/target/*.jar, dependency-check-report/**, trivy-report.json, gitleaks-report.json, zap-report.html', allowEmptyArchive: true
        }
    }
}
