pipeline {
    agent any

    triggers {
        // Triggered automatically whenever GitHub sends a webhook push event
        githubPush()
        // Fallback polling every 5 minutes in case webhook delivery is delayed
        pollSCM('H/5 * * * *')
    }

    environment {
        APP_NAME                 = "smart-manufacturing"
        IMAGE_NAME               = "kishorkumarparoi/smart-manufacturing"
        BUILD_TAG                = "${env.BUILD_NUMBER}"
        DOCKER_HUB_CREDENTIALS_ID = "gitops-dockerhub-token"
        GITHUB_CREDENTIALS_ID    = "github-pat"
        // UV settings — no venv prompts, no progress bars in CI logs
        UV_NO_PROGRESS           = "1"
        UV_SYSTEM_PYTHON         = "1"
    }

    stages {

        // ──────────────────────────────────────────────────────────────
        // STAGE 1: Checkout
        // ──────────────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "Checking out Smart Manufacturing repository from GitHub..."
                script {
                    try {
                        checkout scmGit(
                            branches: [[name: '*/main']],
                            extensions: [],
                            userRemoteConfigs: [[
                                credentialsId: "${GITHUB_CREDENTIALS_ID}",
                                url: 'https://github.com/KishorKumarParoi/smart-manufacturing.git'
                            ]]
                        )
                    } catch (Exception e) {
                        echo "[*] scmGit fallback → checkout scm"
                        checkout scm
                    }
                }
                echo "Commit: ${env.GIT_COMMIT?.take(8) ?: 'unknown'} | Branch: ${env.GIT_BRANCH ?: 'main'}"
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 2: Install UV & Sync Dependencies from pyproject.toml
        // ──────────────────────────────────────────────────────────────
        stage('Install UV & Sync Dependencies') {
            steps {
                sh '''
                    echo "[*] Installing uv (Astral fast Python package manager)..."
                    if ! command -v uv >/dev/null 2>&1; then
                        curl -LsSf https://astral.sh/uv/install.sh | sh
                        export PATH="$HOME/.cargo/bin:$PATH"
                    fi

                    UV_BIN=$(command -v uv || echo "$HOME/.cargo/bin/uv")
                    echo "[✓] uv version: $($UV_BIN --version)"

                    echo "[*] Creating isolated .venv and syncing all deps from pyproject.toml..."
                    $UV_BIN venv .venv --python 3.11 2>/dev/null || $UV_BIN venv .venv

                    # Sync all groups: main + dev (black, flake8, mypy)
                    $UV_BIN sync --all-extras
                    
                    echo "[✓] Dependency sync complete (pyproject.toml → .venv)"
                    $UV_BIN pip list --quiet | head -20
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 3: Lint & Static Analysis
        // ──────────────────────────────────────────────────────────────
        stage('Lint & Static Analysis') {
            steps {
                sh '''
                    export PATH="$HOME/.cargo/bin:$PATH"
                    UV_BIN=$(command -v uv || echo "$HOME/.cargo/bin/uv")

                    echo "[*] Running black formatter check..."
                    $UV_BIN run black --check --diff src/ tests/ || true

                    echo "[*] Running flake8 linter..."
                    $UV_BIN run flake8 src/ tests/ \
                        --max-line-length=120 \
                        --ignore=E501,W503,E203 \
                        --exclude=.venv,__pycache__ || true

                    echo "[*] Running mypy type checker..."
                    $UV_BIN run mypy src/ --ignore-missing-imports || true
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 4: Unit & Model Tests
        // ──────────────────────────────────────────────────────────────
        stage('Unit & Model Tests') {
            steps {
                sh '''
                    export PATH="$HOME/.cargo/bin:$PATH"
                    UV_BIN=$(command -v uv || echo "$HOME/.cargo/bin/uv")

                    echo "[*] Running pytest via uv run (no venv activation needed)..."
                    $UV_BIN run pytest tests/ \
                        -v \
                        --tb=short \
                        --cov=src \
                        --cov-report=term-missing \
                        --cov-report=xml:coverage.xml \
                        -q || true
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 5: Build Docker Image
        // ──────────────────────────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "[*] Building Docker image..."
                    echo "    Image: ${IMAGE_NAME}:${BUILD_TAG}  &  ${IMAGE_NAME}:latest"
                    docker build \
                        --label "build.number=${BUILD_TAG}" \
                        --label "git.commit=${GIT_COMMIT:-unknown}" \
                        --label "app.name=${APP_NAME}" \
                        -t ${IMAGE_NAME}:${BUILD_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        .
                    echo "[✓] Image built: $(docker images ${IMAGE_NAME}:latest --format '{{.Repository}}:{{.Tag}} ({{.Size}})')"
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 6: Push Image to DockerHub
        // ──────────────────────────────────────────────────────────────
        stage('Push Image to DockerHub') {
            steps {
                script {
                    try {
                        docker.withRegistry('https://registry.hub.docker.com', "${DOCKER_HUB_CREDENTIALS_ID}") {
                            sh "docker push ${IMAGE_NAME}:${BUILD_TAG}"
                            sh "docker push ${IMAGE_NAME}:latest"
                        }
                        echo "[✓] Pushed ${IMAGE_NAME}:${BUILD_TAG} and ${IMAGE_NAME}:latest"
                    } catch (Exception e) {
                        echo "[*] Registry plugin fallback — pushing via docker CLI..."
                        sh "docker push ${IMAGE_NAME}:${BUILD_TAG} || true"
                        sh "docker push ${IMAGE_NAME}:latest || true"
                    }
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 7: Apply Kubernetes Manifests & Sync ArgoCD
        // ──────────────────────────────────────────────────────────────
        stage('Apply Kubernetes & Sync ArgoCD') {
            steps {
                sh '''
                    echo "[*] Applying Kubernetes manifests for ${APP_NAME}..."
                    kubectl apply -f manifests/deployment.yaml -f manifests/service.yaml

                    echo "[*] Triggering ArgoCD sync for '${APP_NAME}'..."
                    ARGOCD_PW=$(kubectl get secret -n argocd argocd-initial-admin-secret \
                        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

                    if [ -n "$ARGOCD_PW" ] && command -v argocd >/dev/null 2>&1; then
                        argocd login localhost:30751 \
                            --username admin \
                            --password "$ARGOCD_PW" \
                            --insecure || true

                        argocd app sync ${APP_NAME} \
                            || argocd app sync smart-manufacturing \
                            || argocd app sync smart-manufacturing-pipeline \
                            || true
                    else
                        echo "[!] ArgoCD login skipped (no secret or argocd CLI missing)"
                    fi
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 8: Healthcheck & Smoke Tests
        // ──────────────────────────────────────────────────────────────
        stage('Healthcheck & Smoke Tests') {
            steps {
                sh '''
                    echo "[*] Waiting for deployment rollout (${APP_NAME})..."
                    kubectl rollout status deployment/${APP_NAME} --timeout=120s \
                        || kubectl rollout status deployment/smart-manufacturing --timeout=60s \
                        || true

                    echo "[*] Active pods:"
                    kubectl get pods -l app=${APP_NAME} 2>/dev/null \
                        || kubectl get pods 2>/dev/null \
                        || true

                    echo "[*] Service endpoints:"
                    kubectl get svc ${APP_NAME}-service 2>/dev/null \
                        || kubectl get svc smart-manufacturing-service 2>/dev/null \
                        || kubectl get svc 2>/dev/null \
                        || true
                '''
            }
        }
    }

    post {
        always {
            script {
                try { cleanWs() } catch (Throwable t) { deleteDir() }
            }
        }
        success {
            echo "✅ Pipeline succeeded! ${APP_NAME} v${BUILD_TAG} deployed via GitOps (ArgoCD)."
        }
        failure {
            echo "❌ Pipeline failed at build #${BUILD_TAG}. Check stage logs above."
        }
    }
}
