#!/usr/bin/env python3
"""
MediHive — Cloud Run Production Deployment Guide
==================================================

This script prints the exact commands and configuration needed to deploy
the MediHive backend to Google Cloud Run with Neon PostgreSQL.

Includes:
  - Docker build & push
  - Firebase Admin SDK setup
  - Google Sheets & Drive configuration
  - Environment variable management
  - Health check validation

Prerequisites:
  - Google Cloud SDK (gcloud CLI)
  - Docker installed
  - GCP project with Cloud Run API enabled
  - Neon PostgreSQL database (neon.tech)
  - Google Service Account (Sheets + Drive access)
  - Firebase project with service account

Usage:
    python scripts/deploy_cloud_run.py
"""

import os
import sys
import textwrap


PROJECT_ID      = os.environ.get('GCP_PROJECT_ID',      'your-gcp-project-id')
REGION          = os.environ.get('GCP_REGION',          'us-east1')
SERVICE_NAME    = os.environ.get('CLOUD_RUN_SERVICE',   'medihive-backend')
IMAGE_NAME      = os.environ.get('CLOUD_RUN_IMAGE',     f'gcr.io/{PROJECT_ID}/{SERVICE_NAME}')


def section(title):
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}\n")


def cmd(description, command):
    print(f"  # {description}")
    print(f"  {command}")
    print()


def main():
    print()
    print("╔══════════════════════════════════════════════════════════╗")
    print("║     MediHive — Cloud Run Production Deployment Guide   ║")
    print("╚══════════════════════════════════════════════════════════╝")

    # ── Step 1: Prerequisites ────────────────────────────────
    section("STEP 1: Prerequisites")

    print("  1. Install Google Cloud SDK:")
    cmd("", "  https://cloud.google.com/sdk/docs/install")

    print("  2. Authenticate:")
    cmd("", "gcloud auth login")

    print("  3. Set the project:")
    cmd("", f"gcloud config set project {PROJECT_ID}")

    print("  4. Enable required APIs:")
    cmd("", f"gcloud services enable run.googleapis.com cloudbuild.googleapis.com")

    print("  5. Install Docker:")
    cmd("", "  https://docs.docker.com/get-docker/")

    # ── Step 2: Neon PostgreSQL Database ─────────────────────
    section("STEP 2: Create Neon PostgreSQL Database")

    print("  1. Go to https://console.neon.tech and create a project")
    print("  2. Copy the connection string:")
    print()
    print("     postgresql://user:password@ep-xxxx-xxxx.us-east-2.aws.neon.tech/medihive?sslmode=require")
    print()
    print("  3. Pooled URL (recommended for serverless):")
    print("     postgresql://user:password@ep-xxxx-xxxx-pooler.us-east-2.aws.neon.tech/medihive?sslmode=require")
    print()

    # ── Step 3: Firebase Setup ──────────────────────────────
    section("STEP 3: Firebase Cloud Messaging Setup")

    print("  1. Go to https://console.firebase.google.com")
    print("  2. Create or select your Firebase project")
    print("  3. Go to Project Settings > Service Accounts")
    print("  4. Click 'Generate New Private Key'")
    print("  5. Save the JSON file (you'll pass it as FIREBASE_SERVICE_ACCOUNT_JSON)")
    print()
    print("  6. Alternatively, for legacy FCM (fallback):")
    print("     Go to Project Settings > Cloud Messaging")
    print("     Copy the Server Key (use as FCM_SERVER_KEY)")
    print()

    # ── Step 4: Google Sheets & Drive Setup ──────────────────
    section("STEP 4: Google Sheets & Drive Configuration")

    print("  Google Sheet ID (MediHive - Patient Records):")
    print("    1NECj89gjbga45i5ZlwwHU04l107vmKbQGrEJLPQBmpY")
    print()
    print("  Drive Folder ID (MediHive Images):")
    print("    1Ogx1JHYBBSLTx4glL4-yhcGPLOdBN0GI")
    print()
    print("  Service Account:")
    print("    medihive-service@medihive-500611.iam.gserviceaccount.com")
    print()
    print("  REQUIRED: Grant EDITOR access to the Sheet AND Folder")
    print("  for the service account above.")
    print()

    # ── Step 5: Build Docker Image ──────────────────────────
    section("STEP 5: Build and Push Docker Image")

    cmd("Build using Cloud Build:", f"gcloud builds submit --tag {IMAGE_NAME} --timeout=15m")
    cmd("Or build locally:", f"docker build -t {SERVICE_NAME} . && docker tag {SERVICE_NAME} {IMAGE_NAME} && docker push {IMAGE_NAME}")

    # ── Step 6: Environment Variables ────────────────────────
    section("STEP 6: Environment Variables")

    print("  ╔══════════════════════════════════════════════════════════════════╗")
    print("  ║  ALL environment variables required for production deployment  ║")
    print("  ╚══════════════════════════════════════════════════════════════════╝")
    print()

    env_vars = [
        ("DATABASE_URL",             "postgresql://user:pass@ep-xxx.tech/medihive?sslmode=require", True,
         "PostgreSQL connection string (Neon)"),
        ("SECRET_KEY",               "<random-64-hex>", True,
         "Flask secret. Generate: python -c \"import secrets; print(secrets.token_hex(32))\""),
        ("JWT_SECRET_KEY",           "<random-64-hex>", True,
         "JWT secret. Same generation as SECRET_KEY."),
        ("MEDIHIVE_CLOUD",           "true", False,
         "Enable cloud mode (required)."),
        ("GOOGLE_CREDENTIALS_JSON",  "{...service account json...}", True,
         "Google service account JSON (minified single line)."),
        ("DRIVE_TOKEN_JSON",         "{...drive oauth token...}", True,
         "Google Drive OAuth token JSON (minified single line)."),
        ("FIREBASE_SERVICE_ACCOUNT_JSON", "{...firebase admin json...}", True,
         "Firebase Admin SDK service account JSON (minified single line)."),
        ("GOOGLE_SHEET_ID",          "1NECj89gjbga45i5ZlwwHU04l107vmKbQGrEJLPQBmpY", False,
         "MediHive Google Sheet ID (do not change)."),
        ("DRIVE_ROOT_FOLDER_ID",     "1Ogx1JHYBBSLTx4glL4-yhcGPLOdBN0GI", False,
         "MediHive Drive folder ID for images (do not change)."),
        ("CLINIC_ID",                "CLI001", False,
         "Default clinic ID for sync routing."),
        ("DB_POOL_MIN",              "0", False,
         "Min pool connections (0 for serverless)."),
        ("DB_POOL_MAX",              "5", False,
         "Max pool connections (keep low for Neon free tier)."),
        ("CONNECT_TIMEOUT",          "10", False,
         "Connection timeout in seconds."),
        ("PYTHONUNBUFFERED",         "1", False,
         "Flush Python logs immediately."),
    ]

    for name, default, secret, desc in env_vars:
        print(f"  {name}")
        print(f"    {desc}")
        if not secret:
            print(f"    Default: {default}")
        print()

    # ── Step 7: Deploy to Cloud Run ──────────────────────────
    section("STEP 7: Deploy to Cloud Run")

    env_var_str = ",".join(
        f"{name}={os.environ.get(name, default)}"
        for name, default, _, _ in env_vars
    )

    deploy_cmd = textwrap.dedent(f"""\
    gcloud run deploy {SERVICE_NAME} \\
        --image {IMAGE_NAME} \\
        --platform managed \\
        --region {REGION} \\
        --memory 512Mi \\
        --cpu 1 \\
        --min-instances 0 \\
        --max-instances 10 \\
        --concurrency 80 \\
        --timeout 300 \\
        --no-cpu-throttling \\
        --allow-unauthenticated \\
        --set-env-vars "{env_var_str}"
    """)

    cmd("Initial deploy:", deploy_cmd.strip())

    cmd("Update existing service:", f"""\
gcloud run deploy {SERVICE_NAME} --image {IMAGE_NAME} --region {REGION} \\
    --update-env-vars "{env_var_str}"
""")

    # ── Step 8: Verify ───────────────────────────────────────
    section("STEP 8: Verify Deployment")

    print("  1. Get the service URL:")
    cmd("", f"gcloud run services describe {SERVICE_NAME} --region {REGION} --format='value(status.url)'")

    print("  2. Check health:")
    cmd("", "curl https://<service-url>/api/health")

    print("  3. Run validation:")
    cmd("", f"python scripts/validate_production.py https://<service-url>")

    print("  4. View logs:")
    cmd("", f"gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name={SERVICE_NAME}' --limit 50")

    # ── Step 9: Update Flutter App ───────────────────────────
    section("STEP 9: Update Flutter App")

    print("  1. Update assets/.env with the production URL:")
    print()
    print("     API_BASE_URL=https://<service-url>/api")
    print("     CLOUD_BASE_URL=https://<service-url>/api")
    print("     CLINIC_ID=CLI001")
    print()
    print("  2. Rebuild APK:")
    cmd("", "flutter build apk --release")
    cmd("(or appbundle)", "flutter build appbundle --release")
    print()

    # ── Summary ──────────────────────────────────────────────
    section("DEPLOYMENT SUMMARY")

    print("  ✅  PostgreSQL (Neon) - auto-suspend recovery, pooled connections")
    print("  ✅  Firebase Admin SDK - secure push notifications")
    print("  ✅  Google Sheets - fixed sheet, service account auth")
    print("  ✅  Google Drive - OAuth token, fixed folder")
    print("  ✅  Patient IDs - P001, P002 format (desktop compatible)")
    print("  ✅  Existing sync architecture - UNCHANGED")
    print("  ✅  Existing device registration - UNCHANGED")
    print("  ✅  No ngrok dependency - Cloud Run HTTPS URL")
    print("  ✅  No laptop dependency - 24/7 cloud availability")
    print()
    print("  Run this script anytime to regenerate the commands:")
    print(f"    python scripts/deploy_cloud_run.py")
    print()

    return 0


if __name__ == '__main__':
    sys.exit(main())
