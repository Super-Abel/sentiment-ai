// Jenkinsfile - Pipeline CI/CD SentimentAI (TP5 - 11 stages)
pipeline {
    agent any

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY   = 'ghcr.io/super-abel'
        IMAGE_TAG  = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }

    stages {

        // ── Stage 1 : Checkout ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branche : ${env.BRANCH_NAME}"
                echo "Commit  : ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        // ── Stage 2 : Lint ─────────────────────────────────────────────────
        stage('Lint') {
            steps {
                sh '''
                    docker run --rm \
                        --volumes-from jenkins \
                        -w "$WORKSPACE" \
                        python:3.12-slim \
                        sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        // ── Stage 3 : IaC Validate ─────────────────────────────────────────
        stage('IaC Validate') {
            steps {
                dir('infra') {
                    sh 'terraform init -backend=false -input=false'
                    sh 'terraform fmt -check'
                    sh 'terraform validate'
                }
            }
        }

        // ── Stage 4 : Build & Test ─────────────────────────────────────────
        stage('Build & Test') {
            steps {
                sh '''
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    docker rm -f test-runner 2>/dev/null || true
                    set +e
                    docker run \
                        -e CI=true \
                        --name test-runner \
                        ${IMAGE_NAME}:${IMAGE_TAG} \
                        pytest tests/ -v \
                            --cov=src \
                            --cov-report=xml:/tmp/coverage.xml \
                            --cov-report=term-missing \
                            --cov-fail-under=70
                    TEST_EXIT_CODE=$?
                    set -e
                    docker cp test-runner:/tmp/coverage.xml ./coverage.xml 2>/dev/null || true
                    docker rm -f test-runner 2>/dev/null || true
                    exit $TEST_EXIT_CODE
                '''
            }
            post {
                failure {
                    echo 'Tests échoués ou coverage insuffisant (< 70%)'
                }
            }
        }

        // ── Stage 5 : SonarQube Analysis ───────────────────────────────────
        stage('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        docker run --rm \
                            --network cicd-network \
                            --volumes-from jenkins \
                            -w "$WORKSPACE" \
                            -e SONAR_HOST_URL="$SONAR_HOST_URL" \
                            -e SONAR_TOKEN="$SONARQUBE_TOKEN" \
                            sonarsource/sonar-scanner-cli:latest \
                            sonar-scanner \
                            -Dsonar.projectKey=sentiment-ai \
                            -Dsonar.projectName=SentimentAI \
                            -Dsonar.projectBaseDir="$WORKSPACE" \
                            -Dsonar.sources=src \
                            -Dsonar.python.version=3.11 \
                            -Dsonar.python.coverage.reportPaths=coverage.xml \
                            -Dsonar.sourceEncoding=UTF-8 \
                            -Dsonar.scanner.metadataFilePath=$WORKSPACE/report-task.txt
                    '''
                }
            }
        }

        // ── Stage 6 : Quality Gate ─────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ── Stage 7 : Security Scan ────────────────────────────────────────
        // Rapport complet HIGH+CRITICAL (information), gate bloquant sur CRITICAL
        // uniquement (les HIGH sans fix compatible avec les dépendances actuelles
        // sont suivis mais n'empêchent pas le déploiement).
        stage('Security Scan') {
            steps {
                sh '''
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        aquasec/trivy:latest image \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \
                        --exit-code 0 \
                        --format table \
                ''' + "${IMAGE_NAME}:${IMAGE_TAG}" + '''
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        aquasec/trivy:latest image \
                        --severity CRITICAL \
                        --ignore-unfixed \
                        --exit-code 1 \
                        --format table \
                ''' + "${IMAGE_NAME}:${IMAGE_TAG}"
            }
            post {
                failure {
                    echo 'Vulnérabilités CRITICAL détectées !'
                    echo 'Corrigez les dépendances avant de déployer.'
                }
            }
        }

        // ── Stage 8 : Push ─────────────────────────────────────────────────
        stage('Push') {
            when { expression { env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main' } }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-token',
                    usernameVariable: 'REGISTRY_USER',
                    passwordVariable: 'REGISTRY_PASS'
                )]) {
                    sh """
                        echo \$REGISTRY_PASS | docker login ghcr.io \
                            -u \$REGISTRY_USER --password-stdin
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
                        docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        // ── Stage 9 : IaC Apply ────────────────────────────────────────────
        // Provisionne SentimentAI + Prometheus + Grafana avec l'image exacte.
        stage('IaC Apply') {
            when { expression { env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main' } }
            steps {
                dir('infra') {
                    sh 'terraform init -input=false'
                    sh """
                        terraform apply -auto-approve \
                            -var='image_tag=${IMAGE_TAG}'
                    """
                }
            }
        }

        // ── Stage 10 : Deploy Staging ──────────────────────────────────────
        // Jenkins tourne lui-même dans un conteneur (DooD) attaché à
        // cicd-network : on vérifie via le nom DNS du conteneur et son port
        // interne, pas via "localhost" (qui désignerait Jenkins lui-même).
        stage('Deploy Staging') {
            when { expression { env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main' } }
            steps {
                sh '''
                    for i in $(seq 1 10); do
                        curl -f http://sentiment-staging:8000/health && exit 0
                        echo "En attente du démarrage du conteneur (tentative $i/10)..."
                        sleep 3
                    done
                    exit 1
                '''
            }
        }

        // ── Stage 11 : Smoke Test ──────────────────────────────────────────
        // Vérifie que l'app, /metrics, Prometheus et Grafana sont opérationnels
        // après déploiement, via leurs noms DNS sur cicd-network.
        stage('Smoke Test') {
            when { expression { env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main' } }
            steps {
                sh '''
                    echo "Attente démarrage (10s)..."
                    sleep 10

                    # 1. L'app répond
                    curl -f http://sentiment-staging:8000/health || exit 1
                    echo "/health OK"

                    # 2. Les métriques sont exposées
                    curl -s http://sentiment-staging:8000/metrics | \
                        grep -q sentiment_predictions_total || exit 1
                    echo "/metrics OK — métriques SentimentAI présentes"

                    # 3. Prometheus scrape l'app
                    sleep 20  # attendre au moins 1 scrape (15s)
                    curl -sg "http://prometheus:9090/api/v1/query?\
query=up{job='sentiment-ai'}" | \
                        grep -q '"value":.*1' || exit 1
                    echo "Prometheus scrape sentiment-ai : UP"

                    # 4. Grafana répond
                    curl -f http://grafana:3000/api/health || exit 1
                    echo "Grafana OK"
                '''
            }
            post {
                failure {
                    sh 'docker logs prometheus || true'
                    sh 'docker logs sentiment-staging || true'
                    echo 'Smoke Test KO — voir logs ci-dessus'
                }
            }
        }
    }

    post {
        always {
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline OK — ${IMAGE_TAG} déployé avec monitoring"
        }
        failure {
            echo 'Pipeline KO'
        }
    }
}
