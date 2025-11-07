pipeline {
    agent any

    environment {
        SONAR_HOST = "http://192.168.13.8:9000"
        EMAIL_TO = "takwa.laffet@esprit.tn"
        GIT_URL = "https://github.com/takwa-laffet/Employees.git"
        GIT_BRANCH = "main"
        SONAR_PROJECT_KEY = "Employees"
        SNYK_BINARY = "/usr/local/bin/snyk"
        APP_URL = "http://192.168.13.8:8060"
        PROMETHEUS_URL = "http://192.168.13.8:9090"
        GRAFANA_URL = "http://192.168.13.8:3000"
        PROMETHEUS_PUSHGATEWAY = "http://192.168.13.8:9091"
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
    }

    tools {
        maven 'Maven'
        jdk 'JDK17'
    }

    stages {

        stage('Init') {
            steps {
                script {
                    env.TODAY = sh(script: "date +%F", returnStdout: true).trim()
                    echo "Pipeline initialized on ${env.TODAY}"
                }
            }
        }

        stage('Checkout Code') {
            steps {
                echo "Checking out project source code..."
                git branch: "${GIT_BRANCH}", url: "${GIT_URL}", credentialsId: 'git-token'
            }
        }

        stage('Setup Database') {
            steps {
                echo "Ensuring MySQL is running and database exists..."
                sh '''
                    sudo service mysql start || true
                    sleep 5
                    mysql -u root -proot -e "CREATE DATABASE IF NOT EXISTS employee_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
                '''
                echo "Database employee_db is ready."
            }
        }

        stage('Security Scan - Gitleaks') {
            steps {
                echo "Running Gitleaks secret scan..."
                sh '''
                    gitleaks detect \
                        --source . \
                        --report-format json \
                        --report-path gitleaks-report.json \
                        --exit-code 1 || true
                    zip gitleaks-report.zip gitleaks-report.json
                '''
                archiveArtifacts artifacts: 'gitleaks-report.zip', onlyIfSuccessful: true
            }
        }

        stage('Build Project') {
            steps {
                echo "Building Maven project..."
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', onlyIfSuccessful: true
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    echo "Building Docker image and pushing to DockerHub..."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD')]) {
                        sh """
                            docker build -t employees-app:${BUILD_NUMBER} .
                            docker tag employees-app:${BUILD_NUMBER} \$DOCKERHUB_USERNAME/employees-app:${BUILD_NUMBER}
                            echo \$DOCKERHUB_PASSWORD | docker login -u \$DOCKERHUB_USERNAME --password-stdin
                            docker push \$DOCKERHUB_USERNAME/employees-app:${BUILD_NUMBER}
                        """
                    }
                }
            }
        }

        stage('Test & Coverage - JaCoCo') {
            steps {
                echo "Running tests and generating JaCoCo coverage..."
                sh 'mvn test jacoco:report'
                archiveArtifacts artifacts: 'target/site/jacoco/**/*', allowEmptyArchive: true
            }
        }

        stage('Security Scan - Trivy') {
            steps {
                echo "Running Trivy scan..."
                sh '''
                    trivy fs . \
                        --exit-code 0 \
                        --severity HIGH,CRITICAL \
                        --format template \
                        --template "@/usr/local/share/trivy/templates/html.tpl" \
                        --output trivy-report.html
                    zip trivy-report.zip trivy-report.html
                '''
                archiveArtifacts artifacts: 'trivy-report.zip', onlyIfSuccessful: true
            }
        }

        stage('Security Scan - Snyk') {
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    sh """
                        echo 'Running Snyk vulnerability scan...'
                        ${SNYK_BINARY} auth \$SNYK_TOKEN
                        ${SNYK_BINARY} test --json > snyk-report.json || true
                        zip snyk-report.zip snyk-report.json
                    """
                }
                archiveArtifacts artifacts: 'snyk-report.zip', onlyIfSuccessful: true
            }
        }

        stage('SAST - SonarQube Analysis') {
            steps {
                echo "Running SonarQube analysis..."
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh """mvn sonar:sonar \
                        -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                        -Dsonar.host.url=${SONAR_HOST} \
                        -Dsonar.login=\$SONAR_TOKEN"""
                }
            }
        }

        stage('Security Scan - Nikto') {
            steps {
                echo "Running Nikto scan..."
                sh """
                    nikto -h ${APP_URL} -o nikto-report.html -Format htm || true
                    zip nikto-report.zip nikto-report.html
                """
                archiveArtifacts artifacts: 'nikto-report.zip', onlyIfSuccessful: true
            }
        }

        stage('Security Scan - OWASP ZAP') {
            steps {
                echo "Running OWASP ZAP baseline scan..."
                sh '''
                    docker run --rm --user root \
                        -v $(pwd):/zap/wrk:rw \
                        ghcr.io/zaproxy/zaproxy:stable \
                        bash -c "chmod -R 777 /zap/wrk && zap-baseline.py -t ${APP_URL} -r zap-report.html || true"
                    
                    zip zap-report.zip zap-report.html
                '''
                archiveArtifacts artifacts: 'zap-report.zip', onlyIfSuccessful: true
            }
        }

        stage('Export Metrics to Prometheus') {
            steps {
                script {
                    echo "Sending build metrics to Prometheus Pushgateway..."
                    def durationSeconds = currentBuild.duration / 1000
                    sh """
                        cat <<EOF | curl --data-binary @- ${PROMETHEUS_PUSHGATEWAY}/metrics/job/${JOB_NAME}/build/${BUILD_NUMBER}
jenkins_build_status{job="${JOB_NAME}",build="${BUILD_NUMBER}"} 1
jenkins_build_duration_seconds{job="${JOB_NAME}",build="${BUILD_NUMBER}"} ${durationSeconds}
EOF
                    """
                }
            }
        }
    }

    post {
        success {
            echo "Build succeeded — exporting Prometheus success metric..."
            sh """
                echo 'jenkins_job_success{job="${JOB_NAME}"} 1' | curl --data-binary @- ${PROMETHEUS_PUSHGATEWAY}/metrics/job/jenkins_success
            """
            emailext(
                subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """<html>
                    <body>
                        <p>Hi Takwa, Jenkins pipeline succeeded!</p>
                        <ul>
                            <li><a href="${PROMETHEUS_URL}">Prometheus Dashboard</a></li>
                            <li><a href="${GRAFANA_URL}">Grafana Dashboard</a></li>
                            <li><a href="${SONAR_HOST}/dashboard?id=${SONAR_PROJECT_KEY}">SonarQube Results</a></li>
                            <li><a href="${BUILD_URL}artifact/gitleaks-report.zip">Gitleaks Report</a></li>
                            <li><a href="${BUILD_URL}artifact/trivy-report.zip">Trivy Report</a></li>
                            <li><a href="${BUILD_URL}artifact/snyk-report.zip">Snyk Report</a></li>
                            <li><a href="${BUILD_URL}artifact/nikto-report.zip">Nikto Report</a></li>
                            <li><a href="${BUILD_URL}artifact/zap-report.zip">OWASP ZAP Report</a></li>
                        </ul>
                    </body>
                </html>""",
                to: "${EMAIL_TO}",
                mimeType: 'text/html'
            )
        }

        failure {
            echo "Build failed — exporting failure metric..."
            sh """
                echo 'jenkins_job_failed{job="${JOB_NAME}"} 1' | curl --data-binary @- ${PROMETHEUS_PUSHGATEWAY}/metrics/job/jenkins_failure
            """
            emailext(
                subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """<html>
                    <body>
                        <p>Jenkins pipeline failed!</p>
                        <p>See logs: <a href="${BUILD_URL}">${BUILD_URL}</a></p>
                    </body>
                </html>""",
                to: "${EMAIL_TO}",
                mimeType: 'text/html'
            )
        }

        always {
            archiveArtifacts artifacts: 'target/*.jar, target/site/jacoco/**/*, trivy-report.zip, snyk-report.zip, gitleaks-report.zip, nikto-report.zip, zap-report.zip', allowEmptyArchive: true
            cleanWs()
        }
    }
}
