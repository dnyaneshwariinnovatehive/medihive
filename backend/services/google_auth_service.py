"""Google OAuth authentication service for MediHive.

Manages the OAuth 2.0 authorization flow, token storage,
and refresh logic for accessing Google APIs.

All Google services should obtain credentials through this class
to avoid duplicated authentication logic.
"""

from __future__ import annotations

import json
import os

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/spreadsheets",
]


class GoogleAuthService:
    """Provides shared Google API credentials from drive_token.json."""

    def __init__(self, token_path: str) -> None:
        self._token_path = token_path
        self._creds: Credentials | None = None
        self._oauth_credentials_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "oauth_credentials.json",
        )

    def get_credentials(self) -> Credentials | None:
        """Load and return credentials from drive_token.json or DRIVE_TOKEN_JSON env var.

        Falls back to the ``DRIVE_TOKEN_JSON`` environment variable when
        the token file is missing (useful in cloud/deployed environments).
        Automatically refreshes the token if it is expired and a
        refresh token is available.  Returns ``None`` when both the
        token file and env var are missing or cannot be parsed.
        """
        token_data = None

        if os.path.exists(self._token_path):
            try:
                with open(self._token_path) as f:
                    token_data = json.load(f)
            except (json.JSONDecodeError, OSError):
                token_data = None

        if token_data is None:
            env_json = os.environ.get('DRIVE_TOKEN_JSON', '')
            if env_json:
                try:
                    token_data = json.loads(env_json)
                except json.JSONDecodeError:
                    token_data = None

        if token_data is None:
            return None

        creds = Credentials(
            token=token_data.get("token"),
            refresh_token=token_data.get("refresh_token"),
            token_uri=token_data.get("token_uri"),
            client_id=token_data.get("client_id"),
            client_secret=token_data.get("client_secret"),
            scopes=token_data.get("scopes"),
        )

        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            self._persist_token(creds)

        self._creds = creds
        return creds

    def get_authorization_url(self, redirect_port: int = 8090) -> str:
        """Build the OAuth consent URL for browser-based authorization.

        Returns a URL the user must visit to grant access. After granting,
        call ``exchange_code_for_token()`` with the authorization code.
        """
        if not os.path.exists(self._oauth_credentials_path):
            raise FileNotFoundError(
                f"OAuth client secrets not found at {self._oauth_credentials_path}. "
                "Download from Google Cloud Console > APIs & Services > Credentials."
            )

        flow = InstalledAppFlow.from_client_secrets_file(
            self._oauth_credentials_path, SCOPES
        )
        flow.redirect_uri = f"http://localhost:{redirect_port}"
        auth_url, _ = flow.authorization_url(
            access_type="offline",
            prompt="consent",
        )
        return auth_url

    def exchange_code_for_token(self, authorization_code: str, redirect_port: int = 8090) -> Credentials:
        """Exchange an authorization code for access/refresh tokens.

        Saves the resulting token to ``drive_token.json`` and returns
        the credentials object.
        """
        if not os.path.exists(self._oauth_credentials_path):
            raise FileNotFoundError(
                f"OAuth client secrets not found at {self._oauth_credentials_path}."
            )

        flow = InstalledAppFlow.from_client_secrets_file(
            self._oauth_credentials_path, SCOPES
        )
        flow.redirect_uri = f"http://localhost:{redirect_port}"
        flow.fetch_token(code=authorization_code)

        creds = flow.credentials
        self._persist_token(creds)
        self._creds = creds
        return creds

    def refresh_token(self) -> Credentials:
        """Manually refresh the stored token and persist the updated value.

        Raises ``RuntimeError`` if no credentials are available to refresh.
        """
        creds = self.get_credentials()
        if creds is None:
            raise RuntimeError(
                "No credentials available to refresh. "
                "Run utils/generate_drive_token.py or call exchange_code_for_token()."
            )
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            self._persist_token(creds)
            self._creds = creds
        return creds

    def revoke_token(self) -> None:
        """Revoke the stored token and delete the token file.

        After revocation, a new authorization flow must be completed.
        """
        creds = self.get_credentials()
        if creds and creds.token:
            try:
                creds.revoke()
            except Exception:
                pass

        if os.path.exists(self._token_path):
            os.remove(self._token_path)

        self._creds = None

    def _persist_token(self, creds: Credentials) -> None:
        """Write the current token state to ``drive_token.json``."""
        token_data = {
            "token": creds.token,
            "refresh_token": creds.refresh_token,
            "token_uri": creds.token_uri,
            "client_id": creds.client_id,
            "client_secret": creds.client_secret,
            "scopes": list(creds.scopes) if creds.scopes else [],
            "expiry": creds.expiry.isoformat() if creds.expiry else "",
        }
        with open(self._token_path, "w") as f:
            json.dump(token_data, f, indent=2)
