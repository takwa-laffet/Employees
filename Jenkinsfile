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
        MYSQL_IMAGE = "mysql:8.0"
    }

    tools {
        maven 'Maven'
        jdk 'JDK17'
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
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
                echo "Checking out source code..."
                git branch: "${GIT_BRANCH}", url: "${GIT_URL}", credentialsId: 'git-token'
            }
        }

        stage('Setup Database in Docker') {
            steps {
                echo "Starting MySQL container..."
                sh '''
                    docker rm -f mysql-container || true
                    docker run -d --name mysql-container \
                        -e MYSQL_ROOT_PASSWORD=root \
                        -e MYSQL_DATABASE=employee_db \
                        -e MYSQL_USER=takwa \
                        -e MYSQL_PASSWORD=1212@Laffet \
                        -p 3306:3306 ${MYSQL_IMAGE}
                    sleep 20
                '''
                echo "MySQL is ready."
            }
        }

        stage('Security Scan - Gitleaks') {
            steps {
                echo "Running Gitleaks secret scan..."
                sh '''
                    gitleaks detect --source . \
                        --report-format json \
                        --report-path gitleaks-report.json || true
                    zip gitleaks-report.zip gitleaks-report.json
                '''
                archiveArtifacts artifacts: 'gitleaks-report.zip', allowEmptyArchive: true
            }
        }

        stage('Build Spring Boot App') {
            steps {
                echo "Building with Maven..."
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true
            }
        }

        stage('Docker Build & Push (App + Database)') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKERHUB_USERNAME',
                        passwordVariable: 'DOCKERHUB_PASSWORD')]) {

                        echo "Building Docker images..."

                        // Build and tag app image
                        sh """
                            docker build -t employees-app:${BUILD_NUMBER} .
                            docker tag employees-app:${BUILD_NUMBER} \$DOCKERHUB_USERNAME/employees-app:${BUILD_NUMBER}
                        """

                        // Tag database image for push
                        sh """
                            docker tag ${MYSQL_IMAGE} \$DOCKERHUB_USERNAME/employees-db:${BUILD_NUMBER}
                        """

                        // Push both images
                        sh """
                            echo \$DOCKERHUB_PASSWORD | docker login -u \$DOCKERHUB_USERNAME --password-stdin
                            docker push \$DOCKERHUB_USERNAME/employees-app:${BUILD_NUMBER}
                            docker push \$DOCKERHUB_USERNAME/employees-db:${BUILD_NUMBER}
                        """

                        echo "App and DB images pushed to DockerHub."
                    }
                }
            }
        }

        stage('Test & Coverage - JaCoCo') {
            steps {
                echo "Running tests..."
                sh 'mvn test jacoco:report'
                archiveArtifacts artifacts: 'target/site/jacoco/**/*', allowEmptyArchive: true
            }
        }

        stage('Security Scan - Trivy') {
            steps {
                echo "Scanning source code with Trivy..."
                sh '''
                    trivy fs . --exit-code 0 \
                        --severity HIGH,CRITICAL \
                        --format template \
                        --template "@/usr/local/share/trivy/templates/html.tpl" \
                        --output trivy-report.html
                    zip trivy-report.zip trivy-report.html
                '''
                archiveArtifacts artifacts: 'trivy-report.zip', allowEmptyArchive: true
            }
        }

        stage('Security Scan - Snyk') {
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    sh """
                        ${SNYK_BINARY} auth \$SNYK_TOKEN
                        ${SNYK_BINARY} test --json > snyk-report.json || true
                        zip snyk-report.zip snyk-report.json
                    """
                }
                archiveArtifacts artifacts: 'snyk-report.zip', allowEmptyArchive: true
            }
        }

        stage('SAST - SonarQube') {
            steps {
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh """mvn sonar:sonar \
                        -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                        -Dsonar.host.url=${SONAR_HOST} \
                        -Dsonar.login=\$SONAR_TOKEN"""
                }
            }
        }

        stage('Deploy Containers for Testing') {
            steps {
                echo "Deploying both containers..."
                sh '''
                    docker rm -f employees-app-test || true
                    docker run -d --name employees-app-test \
                        --link mysql-container:mysql \
                        -e SPRING_DATASOURCE_URL=jdbc:mysql://mysql:3306/employee_db?useSSL=false&serverTimezone=UTC \
                        -e SPRING_DATASOURCE_USERNAME=takwa \
                        -e SPRING_DATASOURCE_PASSWORD=1212@Laffet \
                        -p 8060:8080 employees-app:${BUILD_NUMBER}
                    sleep 15
                '''
            }
        }

        stage('Security Scan - Nikto') {
            steps {
                echo "Running Nikto scan..."
                sh """
                    nikto -h ${APP_URL} -o nikto-report.html -Format htm || true
                    zip nikto-report.zip nikto-report.html
                """
                archiveArtifacts artifacts: 'nikto-report.zip', allowEmptyArchive: true
            }
        }

        stage('Security Scan - OWASP ZAP') {
            steps {
                echo "Running OWASP ZAP..."
                sh '''
                    docker run --rm --user root \
                        -v $(pwd):/zap/wrk:rw \
                        ghcr.io/zaproxy/zaproxy:stable \
                        bash -c "chmod -R 777 /zap/wrk && zap-baseline.py -t ${APP_URL} -r zap-report.html || true"
                    zip zap-report.zip zap-report.html
                '''
                archiveArtifacts artifacts: 'zap-report.zip', allowEmptyArchive: true
            }
        }

        stage('Prometheus Metrics') {
            steps {
                script {
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
            echo "✅ Build and Deployment Successful!"
            emailext(
                subject: "✅ SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """<html>
                    <body>
                        <h3>DevSecOps Pipeline Success 🎉</h3>
                        <p>Backend and database images have been pushed to Docker Hub.</p>
                        <ul>
                            <li><a href="${SONAR_HOST}/dashboard?id=${SONAR_PROJECT_KEY}">SonarQube Results</a></li>
                            <li><a href="${BUILD_URL}artifact/trivy-report.zip">Trivy Report</a></li>
                            <li><a href="${BUILD_URL}artifact/snyk-report.zip">Snyk Report</a></li>
                            <li><a href="${BUILD_URL}artifact/gitleaks-report.zip">Gitleaks Report</a></li>
                            <li><a href="${BUILD_URL}artifact/nikto-report.zip">Nikto Report</a></li>
                            <li><a href="${BUILD_URL}artifact/zap-report.zip">ZAP Report</a></li>
                        </ul>
                    </body>
                </html>""",
                to: "${EMAIL_TO}",
                mimeType: 'text/html'
            )
        }

        failure {
            echo "❌ Pipeline failed."
            emailext(
                subject: "❌ FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """<html><body>
                    <p>Pipeline failed! Check logs: <a href="${BUILD_URL}">${BUILD_URL}</a></p>
                </body></html>""",
                to: "${EMAIL_TO}",
                mimeType: 'text/html'
            )
        }

        always {
            echo "🧹 Cleaning up containers..."
            sh '''
                docker stop employees-app-test mysql-container || true
                docker rm employees-app-test mysql-container || true
            '''
            cleanWs()
        }
    }
}
