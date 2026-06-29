"""
Run this ONE TIME from your project root:

    python generate_drive_token.py

What happens:
  1. Browser opens automatically
  2. Sign in with YOUR Google account (same account that owns Clinic_Data folder)
  3. Click Allow
  4. drive_token.json gets created in your project root
  5. Done — never run this again unless you delete drive_token.json

drive_token.json auto-refreshes itself when expired.
"""

from google_auth_oauthlib.flow import InstalledAppFlow
import os

SCOPES = ["https://www.googleapis.com/auth/drive"]

CLIENT_SECRET_FILE = "oauth_credentials.json"

if not os.path.exists(CLIENT_SECRET_FILE):
    print(f"ERROR: {CLIENT_SECRET_FILE} not found in current folder.")
    print("Download it from Google Cloud Console:")
    print("  APIs & Services -> Credentials -> OAuth 2.0 Client IDs -> Download JSON")
    print("  Rename it to oauth_credentials.json and place it here.")
    exit(1)

print("Opening browser for Google login...")
print("Sign in with the Google account that owns the Clinic_Data Drive folder.\n")

flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET_FILE, SCOPES)
creds = flow.run_local_server(port=0)

token_path = "drive_token.json"
with open(token_path, "w", encoding="utf-8") as f:
    f.write(creds.to_json())

print()
print("----------------------------------------")
print(f"SUCCESS — {token_path} created!")
print("Now copy drive_token.json to your project root:")
print(r"  D:\MediHive\MediHive\MediHive\drive_token.json")
print()
print("Then restart the app:")
print("  python -m backend.app")
print("----------------------------------------")