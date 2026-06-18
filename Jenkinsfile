// Jenkinsfile - Pipeline CI/CD SentimentAI
pipeline {
    agent any  // s'exécute sur n'importe quel agent disponible

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY   = 'ghcr.io/super-abel'
        // IMAGE_TAG = SHA Git court du commit (ex : a3f8c12)
        // Chaque build produit une image taguée de façon unique et traçable
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
        // Analyse statique du code Python avec flake8.
        // Lance flake8 dans un conteneur éphémère python:3.12-slim :
        // aucune dépendance sur l'agent Jenkins.
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

        // ── Stage 3 : Build & Test ─────────────────────────────────────────
        // Construit l'image Docker taguée avec le SHA Git,
        // puis lance pytest à l'intérieur de cette image.
        // --cov-fail-under=70 : le pipeline échoue si la couverture < 70 %.
        stage('Build & Test') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                sh """
                    docker run --rm \
                        ${IMAGE_NAME}:${IMAGE_TAG} \
                        pytest tests/ -v \
                            --cov=src \
                            --cov-report=xml:coverage.xml \
                            --cov-report=term-missing \
                            --cov-fail-under=70
                """
            }
            post {
                failure {
                    echo 'Tests échoués ou coverage insuffisant (< 70%)'
                }
            }
        }

        // ── Stage 4 : Push ─────────────────────────────────────────────────
        // Pousse l'image vers ghcr.io UNIQUEMENT sur la branche main.
        // Les branches feature sont buildées/testées mais leurs images
        // ne polluent pas le registry.
        stage('Push') {
            when { branch 'main' }
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
    }

    post {
        always {
            // Nettoyer les conteneurs de test, qu'il y ait succès ou échec
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline réussi ! Image : ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline échoué. Consultez les logs ci-dessus.'
        }
    }
}
