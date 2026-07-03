<#
.SYNOPSIS
    MediHive Production Deployment Script for Google Cloud Run
.DESCRIPTION
    Deploys the MediHive backend to Google Cloud Run with PostgreSQL,
    Firebase Cloud Messaging, Google Sheets, and Google Drive integration.
.PARAMETER ProjectId
    Google Cloud Project ID
.PARAMETER Region
    Google Cloud Region (default: us-east1)
.PARAMETER ServiceName
    Cloud Run service name (default: medihive-backend)
.PARAMETER DatabaseUrl
    PostgreSQL connection string (Neon)
.PARAMETER GoogleCredentialsJson
    Google service account JSON (minified)
.PARAMETER DriveTokenJson
    Google Drive OAuth token JSON (minified)
.PARAMETER FirebaseServiceAccountJson
    Firebase Admin SDK service account JSON (minified)
.PARAMETER SecretKey
    Flask secret key (random 64 hex chars)
.PARAMETER JwtSecretKey
    JWT secret key (random 64 hex chars)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,

    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east1",

    [Parameter(Mandatory=$false)]
    [string]$ServiceName = "medihive-backend",

    [Parameter(Mandatory=$true)]
    [string]$DatabaseUrl,

    [Parameter(Mandatory=$true)]
    [string]$GoogleCredentialsJson,

    [Parameter(Mandatory=$true)]
    [string]$DriveTokenJson,

    [Parameter(Mandatory=$true)]
    [string]$FirebaseServiceAccountJson,

    [Parameter(Mandatory=$true)]
    [string]$SecretKey,

    [Parameter(Mandatory=$true)]
    [string]$JwtSecretKey
)

$ErrorActionPreference = "Stop"
$ImageName = "gcr.io/$ProjectId/$ServiceName"

Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     MediHive Production Deployment to Cloud Run        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Step 1: Verify prerequisites
Write-Host "`n[Step 1] Verifying prerequisites..." -ForegroundColor Yellow
try {
    $gcloudVersion = gcloud --version
    Write-Host "  ✓ gcloud CLI found" -ForegroundColor Green
} catch {
    Write-Host "  ✗ gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Red
    exit 1
}

try {
    $dockerVersion = docker --version
    Write-Host "  ✓ Docker found" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Docker not found. Install Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Step 2: Authenticate and set project
Write-Host "`n[Step 2] Configuring GCP project..." -ForegroundColor Yellow
gcloud config set project $ProjectId
gcloud services enable run.googleapis.com cloudbuild.googleapis.com
Write-Host "  ✓ GCP project configured: $ProjectId" -ForegroundColor Green

# Step 3: Build and push Docker image
Write-Host "`n[Step 3] Building and pushing Docker image..." -ForegroundColor Yellow
Write-Host "  Image: $ImageName" -ForegroundColor Gray
gcloud builds submit --tag $ImageName --timeout=15m
Write-Host "  ✓ Image built and pushed" -ForegroundColor Green

# Step 4: Deploy to Cloud Run
Write-Host "`n[Step 4] Deploying to Cloud Run..." -ForegroundColor Yellow

$envVars = @(
    "DATABASE_URL=$DatabaseUrl",
    "MEDIHIVE_CLOUD=true",
    "SECRET_KEY=$SecretKey",
    "JWT_SECRET_KEY=$JwtSecretKey",
    "GOOGLE_CREDENTIALS_JSON=$GoogleCredentialsJson",
    "DRIVE_TOKEN_JSON=$DriveTokenJson",
    "FIREBASE_SERVICE_ACCOUNT_JSON=$FirebaseServiceAccountJson",
    "GOOGLE_SHEET_ID=1NECj89gjbga45i5ZlwwHU04l107vmKbQGrEJLPQBmpY",
    "DRIVE_ROOT_FOLDER_ID=1Ogx1JHYBBSLTx4glL4-yhcGPLOdBN0GI",
    "CLINIC_ID=CLI001",
    "DB_POOL_MIN=0",
    "DB_POOL_MAX=5",
    "CONNECT_TIMEOUT=10",
    "PYTHONUNBUFFERED=1"
)

$envVarString = ($envVars -join ",")

gcloud run deploy $ServiceName `
    --image $ImageName `
    --platform managed `
    --region $Region `
    --memory 512Mi `
    --cpu 1 `
    --min-instances 0 `
    --max-instances 10 `
    --concurrency 80 `
    --timeout 300 `
    --no-cpu-throttling `
    --allow-unauthenticated `
    --set-env-vars "$envVarString"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Deployment failed" -ForegroundColor Red
    exit 1
}

# Step 5: Get service URL
Write-Host "`n[Step 5] Getting service URL..." -ForegroundColor Yellow
$serviceUrl = gcloud run services describe $ServiceName --region $Region --format='value(status.url)'
Write-Host "  ✓ Service URL: $serviceUrl" -ForegroundColor Green

# Step 6: Verify health endpoint
Write-Host "`n[Step 6] Verifying health endpoint..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
try {
    $healthResponse = Invoke-RestMethod -Uri "$serviceUrl/api/health" -TimeoutSec 10
    Write-Host "  ✓ Health check passed: $($healthResponse | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Health check failed: $_" -ForegroundColor Yellow
    Write-Host "  Check Cloud Run logs for details." -ForegroundColor Yellow
}

# Step 7: Output summary
Write-Host "`n══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Service URL:  $serviceUrl" -ForegroundColor White
Write-Host "  Region:       $Region" -ForegroundColor White
Write-Host "  Project:      $ProjectId" -ForegroundColor White
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Update assets/.env with the service URL:" -ForegroundColor White
Write-Host "     API_BASE_URL=$serviceUrl/api" -ForegroundColor Green
Write-Host "     CLOUD_BASE_URL=$serviceUrl/api" -ForegroundColor Green
Write-Host "  2. Update assets/.env.example with the URL" -ForegroundColor White
Write-Host "  3. Rebuild and distribute Flutter APK:" -ForegroundColor White
Write-Host "     flutter build apk --release" -ForegroundColor Green
Write-Host "  4. View logs:" -ForegroundColor White
Write-Host "     gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$ServiceName' --limit 50" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
