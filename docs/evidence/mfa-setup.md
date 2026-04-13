# MFA Support Path — Gitea TOTP Setup and Test Checklist

Gitea ships with built-in TOTP (Time-based One-Time Password) two-factor
authentication. This document records the exact steps to enable TOTP for
the admin account and provides a test checklist for evidence capture.

> **BoK relevance:** Multi-factor authentication is a Zero Trust requirement.
> Even with `DISABLE_REGISTRATION=true`, the single admin account benefits from
> MFA to prevent credential-only compromise.

---

## Prerequisites

- Admin account must already exist (see `containers/gitea/README.md` — admin
  user is recreated after each container restart)
- A TOTP app: Google Authenticator, Authy, or any RFC 6238 compatible app
- Access to the Gitea web UI: `https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io`

---

## Setup Steps

### 1. Log in as Admin

1. Open the Gitea URL in a browser
2. Sign in with `gitea-admin` and the password from Key Vault (`gitea-admin-password`)

### 2. Navigate to Two-Factor Settings

1. Click your avatar (top-right) → **Settings**
2. Left sidebar → **Security**
3. Find the **Two-Factor Authentication** section
4. Click **Enroll**

### 3. Scan QR Code

1. Open your TOTP app
2. Tap "Add account" / "Scan QR code"
3. Scan the QR code shown on screen
4. **Save the scratch codes** shown — these are one-time backup codes if you
   lose access to your TOTP device. Store securely (e.g. Key Vault as a new secret).

### 4. Confirm Enrollment

1. Enter the 6-digit code from your TOTP app into the confirmation field
2. Click **Submit**
3. Gitea confirms: "Two-Factor Authentication is now enabled"

---

## Test Checklist

After enabling TOTP, verify all three flows and capture screenshots as evidence:

### Test A — Password only (MFA bypassed — should FAIL after enrollment)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Go to `/user/login` | Login form displayed |
| 2 | Enter correct username + password, click Sign In | **Redirected to TOTP prompt** (not dashboard) |
| 3 | Close browser without entering TOTP code | Session not established |

- [ ] Confirmed: password alone is insufficient after TOTP enrollment
- [ ] Screenshot saved: `docs/evidence/phase5-mfa/screenshot-totp-prompt.png`

### Test B — Password + valid TOTP code (should PASS)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Enter correct username + password | TOTP prompt appears |
| 2 | Enter current 6-digit code from TOTP app | **Logged in — dashboard visible** |

- [ ] Confirmed: password + valid TOTP grants access
- [ ] Screenshot saved: `docs/evidence/phase5-mfa/screenshot-totp-success.png`

### Test C — Password + invalid TOTP code (should FAIL)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Enter correct username + password | TOTP prompt appears |
| 2 | Enter an intentionally wrong code (e.g. `000000`) | **"Invalid two-factor code"** error |
| 3 | Session not established | Login page re-shown |

- [ ] Confirmed: wrong TOTP code is rejected
- [ ] Screenshot saved: `docs/evidence/phase5-mfa/screenshot-totp-invalid.png`

---

## Disabling TOTP (if the container restarts)

Because the SQLite DB is on EmptyDir, the admin account and TOTP enrollment are
lost on container restart. After recreating the admin user, TOTP must be
re-enrolled from step 1 above.

For production, migrate to Azure Database for PostgreSQL Flexible Server
(persistent DB) so MFA enrollment survives restarts.

---

## BoK Mapping

| Control | Evidence |
|---------|---------|
| Multi-factor authentication | TOTP enrollment via Gitea Settings → Security |
| Zero Trust (verify explicitly) | MFA enforced even for admin; password alone insufficient |
| Key management | Scratch codes stored in Key Vault; no plaintext backup in repo |
