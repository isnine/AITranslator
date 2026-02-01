# Key Rotation / Revocation Checklist

## Overview

All secrets exposed in the git history MUST be rotated/revoked before open-sourcing, regardless of whether the history is cleaned. Assume all exposed secrets are compromised.

---

## Exposed Secrets Summary

| Secret Type | Value (Partial) | Status | Priority |
|-------------|-----------------|--------|----------|
| Azure OpenAI API Key | `[REDACTED]` | EXPOSED | CRITICAL |
| HMAC Secret | `[REDACTED]` | EXPOSED | CRITICAL |
| Azure Endpoint | `[REDACTED]` | EXPOSED | HIGH |

---

## 1. Azure OpenAI API Key

**Exposed Value:** `[REDACTED - check your Azure Portal]`

### Rotation Steps

1. **Login to Azure Portal**
   - URL: https://portal.azure.com
   - Navigate to: Azure OpenAI Service > Your Resource > Keys and Endpoint

2. **Regenerate Key**
   - Click "Regenerate Key1" or "Regenerate Key2" (whichever was exposed)
   - Confirm regeneration
   - Copy the new key

3. **Update Dependent Services**
   - If this key is used in production Cloudflare Workers, update the worker secrets
   - Update any CI/CD environment variables

4. **Verify Old Key is Invalid**
   ```bash
   # Test that old key no longer works
   curl -X POST "https://YOUR_ENDPOINT/openai/deployments/YOUR_DEPLOYMENT/chat/completions?api-version=2025-01-01-preview" \
     -H "api-key: YOUR_OLD_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"messages":[{"role":"user","content":"test"}]}'
   # Should return 401 Unauthorized
   ```

5. **Check Azure Activity Logs**
   - Review Azure Portal > Activity Log
   - Look for any suspicious API calls with the old key
   - Time range: Since the key was first committed to git

### Location
- Azure Portal: https://portal.azure.com
- Resource Group: [Your resource group]
- Resource Name: [Your Azure OpenAI resource name]

---

## 2. HMAC Secret (Built-in Cloud Service)

**Exposed Value:** `[REDACTED - check your Cloudflare Worker settings]`

### Rotation Steps

1. **Generate New Secret**
   ```bash
   # Generate a new 256-bit (32-byte) secret
   openssl rand -hex 32
   # Example output: a1b2c3d4e5f6... (64 hex characters)
   ```

2. **Update Cloudflare Worker**
   - Login to Cloudflare Dashboard: https://dash.cloudflare.com
   - Navigate to: Workers & Pages > `translator-api` (or `aitranslator`)
   - Go to Settings > Variables
   - Update the `HMAC_SECRET` (or similar) environment variable
   - Deploy the worker

3. **Update Local Configuration**
   - Create/update `Secrets.plist` with the new secret
   - Or set environment variable: `AITRANSLATOR_BUILTIN_CLOUD_SECRET`

4. **Verify New Secret Works**
   - Build and run the app locally
   - Make a translation request
   - Confirm it succeeds with the new secret

5. **Verify Old Secret is Rejected**
   - Temporarily test with old secret to confirm worker rejects it

### Location
- Cloudflare Dashboard: https://dash.cloudflare.com
- Worker Name: `translator-api` or `aitranslator`
- Secret Variable: `HMAC_SECRET` or `SHARED_SECRET`

---

## 3. Azure Endpoint

**Exposed Value:** `[REDACTED]`

### Actions Required

The endpoint itself is not a secret, but its exposure combined with the API key increases risk.

1. **Consider Resource Renaming** (Optional)
   - If you want to obscure the endpoint, you can:
     - Create a new Azure OpenAI resource with a different name
     - Migrate deployments
     - Delete the old resource
   - This is optional and may be overkill

2. **Enable Additional Security**
   - Azure Portal > Your OpenAI Resource > Networking
   - Enable private endpoints if possible
   - Add IP restrictions if applicable
   - Enable Azure AD authentication as an additional layer

3. **Review Access Logs**
   - Check Azure Monitor for any unauthorized access
   - Set up alerts for unusual usage patterns

---

## Rotation Order

Execute in this order to minimize service disruption:

1. **First**: Generate all new secrets (don't apply yet)
2. **Second**: Update the Cloudflare Worker with new HMAC secret
3. **Third**: Update local app configuration with new secrets
4. **Fourth**: Test that app works with new configuration
5. **Fifth**: Rotate Azure API key in Azure Portal
6. **Sixth**: If using Azure directly (not via worker), update app config
7. **Seventh**: Verify all old credentials are rejected

---

## Post-Rotation Verification

### Checklist

- [ ] New Azure API key generated
- [ ] Old Azure API key confirmed invalid (401 response)
- [ ] New HMAC secret generated
- [ ] Cloudflare Worker updated with new HMAC secret
- [ ] Local Secrets.plist updated with new secrets
- [ ] App builds and runs successfully
- [ ] Translation requests work with new configuration
- [ ] Old HMAC secret rejected by worker
- [ ] Azure Activity Logs reviewed for suspicious activity
- [ ] New secrets stored securely (password manager, etc.)

---

## Ongoing Security Recommendations

1. **Secret Rotation Schedule**
   - Rotate all secrets every 90 days
   - Set calendar reminders

2. **Access Control**
   - Use Azure RBAC to limit who can view/manage keys
   - Enable MFA for all Azure and Cloudflare accounts

3. **Monitoring**
   - Set up Azure Monitor alerts for unusual API usage
   - Set up Cloudflare analytics alerts

4. **Pre-commit Hooks**
   - Install `gitleaks` or similar to prevent future secret commits:
     ```bash
     brew install gitleaks
     gitleaks detect --source . --verbose
     ```

5. **GitHub Secret Scanning**
   - Enable GitHub secret scanning on the repository
   - Enable push protection to block commits with secrets
