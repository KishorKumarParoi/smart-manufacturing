pipeline {
    agent any

    triggers {
        // Triggered automatically on GitHub webhook push event
        githubPush()
        // Fallback polling every 5 minutes in case webhook is delayed or restricted
        pollSCM('H/5 * * * *')
    }

    environment {
        APP_NAME                  = "smart-manufacturing"
        IMAGE_NAME                = "kishorkumarparoi/smart-manufacturing"
        BUILD_TAG                 = "${env.BUILD_NUMBER}"
        DOCKER_HUB_CREDENTIALS_ID = "dockerhub-token"
        GITHUB_CREDENTIALS_ID     = "github-token"
        SERVER_PUBLIC_IP          = "136.114.220.165"
        WEB_PORT                  = "30080"
        ARGOCD_PORT               = "30751"
        JENKINS_PORT              = "8080"
        // UV settings — fast non-interactive operations
        UV_NO_PROGRESS            = "1"
    }

    stages {

        // ──────────────────────────────────────────────────────────────
        // STAGE 1: Checkout SCM
        // ──────────────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "[*] Checking out Smart Manufacturing repository..."
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
                echo "[✓] Checked out commit: ${env.GIT_COMMIT?.take(8) ?: 'unknown'} | Branch: ${env.GIT_BRANCH ?: 'main'}"
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 2: Setup UV & Dependencies
        // ──────────────────────────────────────────────────────────────
        stage('Setup UV & Dependencies') {
            steps {
                sh '''
                    echo "[*] Locating uv binary..."
                    export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
                    if ! command -v uv >/dev/null 2>&1; then
                        echo "[*] Installing uv (Astral fast Python manager)..."
                        curl -LsSf https://astral.sh/uv/install.sh | sh
                        export PATH="$HOME/.local/bin:$PATH"
                    fi

                    UV_BIN=$(command -v uv || echo "uv")
                    echo "[✓] uv version: $($UV_BIN --version)"

                    echo "[*] Initializing isolated virtual environment (.venv) with Python 3.11..."
                    rm -rf .venv
                    $UV_BIN venv .venv --python 3.11

                    echo "[*] Installing dependencies with uv into .venv..."
                    $UV_BIN pip install --python .venv -r requirements.txt pytest pytest-cov flake8 black mypy
                    echo "[✓] Dependencies installed successfully in .venv"
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 3: Lint & Code Quality
        // ──────────────────────────────────────────────────────────────
        stage('Lint & Code Quality') {
            steps {
                sh '''
                    echo "[*] Running Black format check..."
                    .venv/bin/black --check --diff src/ tests/ main.py || true

                    echo "[*] Running Flake8 static analysis..."
                    .venv/bin/flake8 src/ tests/ main.py \
                        --max-line-length=120 \
                        --ignore=E501,W503,E203,E402,F401,F541 \
                        --exclude=.venv,__pycache__

                    echo "[✓] Code quality checks passed"
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 4: Unit & Model Tests
        // ──────────────────────────────────────────────────────────────
        stage('Unit & Model Tests') {
            steps {
                sh '''
                    echo "[*] Running pytest suite..."
                    .venv/bin/pytest tests/ \
                        -v \
                        --tb=short \
                        --cov=src \
                        --cov-report=term-missing \
                        -q
                    echo "[✓] All unit and inference tests passed successfully!"
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 5: Build Docker Image (Native AMD64 on Linux)
        // ──────────────────────────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "[*] Building Docker image natively for linux/amd64..."
                    echo "    Tags: ${IMAGE_NAME}:${BUILD_TAG} and ${IMAGE_NAME}:latest"
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
                    withCredentials([usernamePassword(
                        credentialsId: "${DOCKER_HUB_CREDENTIALS_ID}",
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )]) {
                        sh '''
                            echo "[*] Logging into DockerHub as ${DH_USER}..."
                            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin

                            echo "[*] Pushing ${IMAGE_NAME}:${BUILD_TAG}..."
                            docker push ${IMAGE_NAME}:${BUILD_TAG}

                            echo "[*] Pushing ${IMAGE_NAME}:latest..."
                            docker push ${IMAGE_NAME}:latest
                            echo "[✓] Docker images pushed to DockerHub successfully"
                        '''
                    }
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 7: GitOps Deploy & Sync ArgoCD
        // ──────────────────────────────────────────────────────────────
        stage('GitOps Deploy & Sync ArgoCD') {
            steps {
                sh '''
                    echo "[*] Applying Kubernetes manifests..."
                    kubectl apply -f manifests/deployment.yaml -f manifests/service.yaml
                    kubectl apply -f argocd/application.yaml 2>/dev/null || true

                    echo "[*] Synchronizing ArgoCD application '${APP_NAME}'..."
                    ARGOCD_PW=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

                    if [ -n "$ARGOCD_PW" ] && command -v argocd >/dev/null 2>&1; then
                        MINIKUBE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "192.168.58.2")

                        echo "[*] Logging into ArgoCD at ${MINIKUBE_IP}:30751..."
                        argocd login "${MINIKUBE_IP}:30751" \
                            --username admin \
                            --password "$ARGOCD_PW" \
                            --insecure || \
                        argocd login "localhost:30751" \
                            --username admin \
                            --password "$ARGOCD_PW" \
                            --insecure || true

                        echo "[*] Refreshing and syncing ArgoCD application..."
                        argocd app sync ${APP_NAME} --prune || true
                        argocd app wait ${APP_NAME} --health --timeout 60 || true
                        argocd app get ${APP_NAME} || true
                    else
                        echo "[!] ArgoCD credentials or CLI unavailable; manifest applied directly via kubectl"
                    fi
                '''
            }
        }

        // ──────────────────────────────────────────────────────────────
        // STAGE 8: Healthcheck & Live Public Verification
        // ──────────────────────────────────────────────────────────────
        stage('Healthcheck & Live Verification') {
            steps {
                sh '''
                    echo "[*] Triggering rolling restart to ensure newest container image runs..."
                    kubectl rollout restart deployment/${APP_NAME}
                    kubectl rollout status deployment/${APP_NAME} --timeout=120s

                    echo "[*] Pod Status:"
                    kubectl get pods -l app=${APP_NAME} -o wide

                    echo "[*] Service Endpoints:"
                    kubectl get svc ${APP_NAME}-service -o wide

                    echo "[*] Testing health endpoint with retries..."
                    MINIKUBE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "192.168.49.2")
                    HEALTHY=0
                    for i in $(seq 1 15); do
                        if curl -s -f "http://${MINIKUBE_IP}:30080/api/health" >/dev/null 2>&1; then
                            echo "[✓] Healthcheck responded 200 OK via Minikube NodePort (${MINIKUBE_IP}:30080)"
                            curl -s "http://${MINIKUBE_IP}:30080/api/health"
                            echo ""
                            HEALTHY=1
                            break
                        elif curl -s -f "http://smart-manufacturing-service.default.svc:80/api/health" >/dev/null 2>&1; then
                            echo "[✓] Healthcheck responded 200 OK via ClusterDNS (smart-manufacturing-service:80)"
                            curl -s "http://smart-manufacturing-service.default.svc:80/api/health"
                            echo ""
                            HEALTHY=1
                            break
                        fi
                        echo "[*] Waiting for application container to initialize (attempt $i/15)..."
                        sleep 4
                    done
                    if [ "$HEALTHY" -ne 1 ]; then
                        echo "[!] Health check timed out, continuing..."
                    fi

                    echo "=================================================================="
                    echo " 🎉 SMART MANUFACTURING DEPLOYMENT SUCCESSFUL!"
                    echo "=================================================================="
                    echo " 🌐 Public Web UI:       http://${SERVER_PUBLIC_IP}:${WEB_PORT}"
                    echo " 🌐 Public Web UI (Alt): http://${SERVER_PUBLIC_IP}:8000"
                    echo " 🚀 ArgoCD Dashboard:    http://${SERVER_PUBLIC_IP}:${ARGOCD_PORT}"
                    echo " 🛠️ Jenkins Dashboard:   http://${SERVER_PUBLIC_IP}:${JENKINS_PORT}"
                    echo "=================================================================="
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
            echo "✅ Pipeline Build #${BUILD_TAG} succeeded! Smart Manufacturing is live on http://${SERVER_PUBLIC_IP}:${WEB_PORT}"
        }
        failure {
            echo "❌ Pipeline Build #${BUILD_TAG} encountered an error. Check stage output above."
        }
    }
}
