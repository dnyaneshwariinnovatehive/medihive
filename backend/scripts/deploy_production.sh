#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# MediHive Production Deployment Script for Google Cloud Run
# ==============================================================
# Usage:
#   chmod +x scripts/deploy_production.sh
#   ./scripts/deploy_production.sh \
#     --project-id=my-project \
#     --database-url="postgresql://..." \
#     --google-credentials='{"type":"service_account",...}' \
#     --drive-token='{"token":"...",...}' \
#     --firebase-service-account='{"type":"service_account",...}' \
#     --secret-key="$(python -c 'import secrets; print(secrets.token_hex(32))')" \
#     --jwt-secret-key="$(python -c 'import secrets; print(secrets.token_hex(32))')"
# ==============================================================

# ─── Parse arguments ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id=*)           PROJECT_ID="${1#*=}" ;;
    --region=*)               REGION="${1#*=}" ;;
    --service-name=*)         SERVICE_NAME="${1#*=}" ;;
    --database-url=*)         DATABASE_URL="${1#*=}" ;;
    --google-credentials=*)   GOOGLE_CREDENTIALS_JSON="${1#*=}" ;;
    --drive-token=*)          DRIVE_TOKEN_JSON="${1#*=}" ;;
    --firebase-service-account=*) FIREBASE_SERVICE_ACCOUNT_JSON="${1#*=}" ;;
    --secret-key=*)           SECRET_KEY="${1#*=}" ;;
    --jwt-secret-key=*)       JWT_SECRET_KEY="${1#*=}" ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

: "${PROJECT_ID:?Must set --project-id}"
: "${DATABASE_URL:?Must set --database-url}"
: "${GOOGLE_CREDENTIALS_JSON:?Must set --google-credentials}"
: "${DRIVE_TOKEN_JSON:?Must set --drive-token}"
: "${FIREBASE_SERVICE_ACCOUNT_JSON:?Must set --firebase-service-account}"
: "${SECRET_KEY:?Must set --secret-key}"
: "${JWT_SECRET_KEY:?Must set --jwt-secret-key}"

REGION="${REGION:-us-east1}"
SERVICE_NAME="${SERVICE_NAME:-medihive-backend}"
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     MediHive Production Deployment to Cloud Run        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── Step 1: Prerequisites ──────────────────────────────────
echo "[Step 1] Verifying prerequisites..."

if ! command -v gcloud &> /dev/null; then
  echo "  ✗ gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "  ✗ Docker not found."
  exit 1
fi
echo "  ✓ All prerequisites met"

# ─── Step 2: Configure GCP ──────────────────────────────────
echo ""
echo "[Step 2] Configuring GCP project: ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com
echo "  ✓ GCP project configured"

# ─── Step 3: Build Docker Image ─────────────────────────────
echo ""
echo "[Step 3] Building and pushing Docker image..."
echo "  Image: ${IMAGE_NAME}"
gcloud builds submit --tag "${IMAGE_NAME}" --timeout=15m
echo "  ✓ Image built and pushed"

# ─── Step 4: Deploy to Cloud Run ────────────────────────────
echo ""
echo "[Step 4] Deploying to Cloud Run..."

gcloud run deploy "${SERVICE_NAME}" \
  --image "${IMAGE_NAME}" \
  --platform managed \
  --region "${REGION}" \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 10 \
  --concurrency 80 \
  --timeout 300 \
  --no-cpu-throttling \
  --allow-unauthenticated \
  --set-env-vars "^@^DATABASE_URL=${DATABASE_URL}@MEDIHIVE_CLOUD=true@SECRET_KEY=${SECRET_KEY}@JWT_SECRET_KEY=${JWT_SECRET_KEY}@GOOGLE_CREDENTIALS_JSON=${GOOGLE_CREDENTIALS_JSON}@DRIVE_TOKEN_JSON=${DRIVE_TOKEN_JSON}@FIREBASE_SERVICE_ACCOUNT_JSON=${FIREBASE_SERVICE_ACCOUNT_JSON}@GOOGLE_SHEET_ID=1NECj89gjbga45i5ZlwwHU04l107vmKbQGrEJLPQBmpY@DRIVE_ROOT_FOLDER_ID=1Ogx1JHYBBSLTx4glL4-yhcGPLOdBN0GI@CLINIC_ID=CLI001@DB_POOL_MIN=0@DB_POOL_MAX=5@CONNECT_TIMEOUT=10@PYTHONUNBUFFERED=1"

echo "  ✓ Deployed to Cloud Run"

# ─── Step 5: Verify ──────────────────────────────────────────
echo ""
echo "[Step 5] Verifying deployment..."
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)')
echo "  Service URL: ${SERVICE_URL}"

sleep 10
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}/api/health" 2>/dev/null || echo "failed")
if [ "$HEALTH" = "200" ]; then
  echo "  ✓ Health check passed (HTTP 200)"
else
  echo "  ⚠ Health check returned HTTP ${HEALTH}"
fi

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  DEPLOYMENT COMPLETE"
echo "══════════════════════════════════════════════════════════"
echo "  Service URL:  ${SERVICE_URL}"
echo "  Region:       ${REGION}"
echo "  Project:      ${PROJECT_ID}"
echo ""
echo "  NEXT STEPS:"
echo "  1. Update assets/.env with the service URL:"
echo "     API_BASE_URL=${SERVICE_URL}/api"
echo "     CLOUD_BASE_URL=${SERVICE_URL}/api"
echo "  2. Update assets/.env.example with the URL"
echo "  3. Rebuild and distribute Flutter APK:"
echo "     flutter build apk --release"
echo "  4. View logs:"
echo "     gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}\" --limit 50"
echo "══════════════════════════════════════════════════════════"
echo ""
