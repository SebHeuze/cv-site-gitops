@echo off
setlocal enabledelayedexpansion

:: CV-Site GitOps Deployment Script for Windows
:: This script bootstraps the entire infrastructure using Argo CD

echo ================================================
echo   CV-Site GitOps Deployment
echo ================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "GITOPS_DIR=%SCRIPT_DIR%.."

:: Check prerequisites
echo [INFO] Checking prerequisites...

where kubectl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] kubectl not found. Please install kubectl.
    exit /b 1
)

where helm >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] helm not found. Please install helm.
    exit /b 1
)

kubectl cluster-info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Cannot connect to Kubernetes cluster.
    exit /b 1
)

echo [INFO] Prerequisites check passed.
echo.

:: Install cert-manager
echo [INFO] Installing cert-manager...

kubectl get namespace cert-manager >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [WARN] cert-manager namespace already exists, skipping...
) else (
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
    echo [INFO] Waiting for cert-manager to be ready...
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
    echo [INFO] cert-manager installed successfully.
)
echo.

:: Install Strimzi operator
echo [INFO] Installing Strimzi Kafka operator...

kubectl create namespace kafka-prd --dry-run=client -o yaml | kubectl apply -f -

kubectl get deployment strimzi-cluster-operator -n kafka-prd >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [WARN] Strimzi operator already installed, skipping...
) else (
    kubectl apply -f "https://strimzi.io/install/latest?namespace=kafka-prd" -n kafka-prd
    echo [INFO] Waiting for Strimzi operator to be ready...
    kubectl wait --for=condition=available --timeout=300s deployment/strimzi-cluster-operator -n kafka-prd
    echo [INFO] Strimzi operator installed successfully.
)
echo.

:: Install Argo CD
echo [INFO] Installing Argo CD...

kubectl apply -f "%GITOPS_DIR%\bootstrap\argocd-namespace.yaml"

kubectl get deployment argocd-server -n argocd >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [WARN] Argo CD already installed, skipping...
) else (
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo [INFO] Waiting for Argo CD to be ready...
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
    echo [INFO] Argo CD installed successfully.
)
echo.

:: Get Argo CD admin password
echo [INFO] Retrieving Argo CD admin password...

for /f "tokens=*" %%a in ('kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath^="{.data.password}"') do set "ENCODED_PASS=%%a"

echo.
echo ================================================
echo   Argo CD Credentials
echo ================================================
echo   Username: admin
echo   Password: (base64 decode the following)
echo   %ENCODED_PASS%
echo.
echo   To decode, run:
echo   powershell -Command "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('%ENCODED_PASS%'))"
echo ================================================
echo.

:: Deploy App of Apps
echo [INFO] Deploying App of Apps...
kubectl apply -f "%GITOPS_DIR%\bootstrap\app-of-apps.yaml"
echo [INFO] App of Apps deployed. Argo CD will now sync all applications.
echo.

echo ================================================
echo   Deployment Complete!
echo ================================================
echo.
echo   To access Argo CD UI, run:
echo   kubectl port-forward svc/argocd-server -n argocd 8080:443
echo.
echo   Then open: https://localhost:8080
echo.
echo   Next Steps:
echo   1. Access Argo CD UI
echo   2. Login with credentials shown above
echo   3. Watch applications sync in the UI
echo   4. Configure DNS records for your domain
echo   5. Update secrets in production values
echo ================================================

endlocal
