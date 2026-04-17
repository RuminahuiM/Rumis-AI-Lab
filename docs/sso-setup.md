# SSO Setup (Azure AD + Application Proxy)

Users access Open WebUI and n8n through Azure Application Proxy, which handles TLS termination and pre-authentication. Both apps use OIDC with Azure AD for single sign-on.

---

## Prerequisites

- Azure AD (Entra ID) tenant with admin access
- Azure AD P1 or P2 license (required for Application Proxy)
- Frontend VM deployed and services running (see [Frontend Setup](frontend-setup.md))

---

## Step 1: Register App — Open WebUI

1. Go to **Azure Portal → Azure Active Directory → App registrations → New registration**
2. Name: `Rumis AI Lab - Open WebUI`
3. Supported account types: **Single tenant**
4. Redirect URI: **Web** → `https://oui.yourdomain.com/oauth/oidc/callback`
5. Click **Register**
6. Note the **Application (client) ID** and **Directory (tenant) ID**
7. Go to **Certificates & secrets → New client secret** → copy the value

Add to `.env`:
```env
AZURE_TENANT_ID=<tenant-id>
OAUTH_CLIENT_ID=<client-id>
OAUTH_CLIENT_SECRET=<client-secret>
```

---

## Step 2: Register App — n8n

1. Go to **App registrations → New registration**
2. Name: `Rumis AI Lab - n8n`
3. Supported account types: **Single tenant**
4. Redirect URI: **Web** → `https://n8n.yourdomain.com/rest/oauth2-credential/callback`
   (verify exact callback path in n8n-oidc documentation)
5. Click **Register**
6. Note the **Application (client) ID**
7. Go to **Certificates & secrets → New client secret** → copy the value

Add to `.env`:
```env
OAUTH_CLIENT_ID_N8N=<client-id>
OAUTH_CLIENT_SECRET_N8N=<client-secret>
```

Restart services after updating `.env`:
```bash
docker compose up -d
```

---

## Step 3: Install App Proxy Connector

The connector runs on the VM and creates an outbound connection to Azure — no inbound firewall rules needed.

```bash
# Download the connector (on the VM)
wget -O connector-installer.exe "https://download.msappproxy.net/subscription/d3c8b69d-6bf7-42be-a529-3fe9c2e70c90/connector/download"
```

Follow Microsoft's guide for Linux connector installation:
[Install Application Proxy connector](https://learn.microsoft.com/en-us/entra/identity/app-proxy/application-proxy-add-on-premises-application)

Alternatively, install the connector on a separate Windows Server VM in the same network.

---

## Step 4: Create Enterprise Applications

### Open WebUI

1. Go to **Azure Portal → Enterprise applications → New application → Create your own application**
2. Name: `Rumis AI Lab - Open WebUI`
3. Select: **Configure Application Proxy for secure remote access**
4. Internal URL: `http://<vm-ip>:3000`
5. External URL: `https://oui.yourdomain.com` (or use the default `*.msappproxy.net`)
6. Pre-authentication: **Azure Active Directory**
7. Connector group: select the group containing the connector on your VM
8. Under **Single sign-on**, select **Header-based** or **OpenID Connect** depending on your setup

### n8n

1. Repeat the above with:
   - Name: `Rumis AI Lab - n8n`
   - Internal URL: `http://<vm-ip>:5678`
   - External URL: `https://n8n.yourdomain.com`

---

## Step 5: Assign Users

For each Enterprise Application:
1. Go to **Users and groups → Add user/group**
2. Select the users or groups that should have access
3. Assign a role (if applicable)

Users not assigned will be denied access at the Azure AD level.

---

## How SSO Works

### Open WebUI
Open WebUI has built-in OIDC support. When a user visits the login page, they see an "Azure AD" login button. Clicking it redirects to Azure AD, authenticates, and returns with a token. Open WebUI creates a local user account automatically on first login (`ENABLE_OAUTH_SIGNUP=true`).

### n8n
The free n8n community edition does not include SSO. We use the **n8n-oidc** community module ([cweagans/n8n-oidc](https://github.com/cweagans/n8n-oidc)) which bolts OIDC onto n8n using its external hooks system. It supports Azure AD, auto-provisions users, and assigns roles.

The module is loaded via the `EXTERNAL_MODULES=n8n-oidc` environment variable in docker-compose.yml.

---

## Troubleshooting

**"AADSTS50011: The redirect URI does not match"**
→ Ensure the redirect URI in the App Registration exactly matches what the app sends. For OpenWebUI: `https://oui.yourdomain.com/oauth/oidc/callback`

**"This corporate app can't be accessed" / 403 from App Proxy**
→ User is not assigned to the Enterprise Application. Go to Users and groups → Add.

**Connector shows offline in Azure Portal**
→ Check the connector service is running on the VM. Verify outbound HTTPS (443) to `*.msappproxy.net` is not blocked.

**n8n-oidc login button doesn't appear**
→ Verify `EXTERNAL_MODULES=n8n-oidc` is set. Check `docker compose logs n8n` for module loading errors. Ensure the n8n-oidc env vars are set.

**SSO works but user has no permissions in n8n**
→ The first user created in n8n (or via OIDC) needs to be promoted to owner. Check n8n-oidc docs for role mapping configuration.
