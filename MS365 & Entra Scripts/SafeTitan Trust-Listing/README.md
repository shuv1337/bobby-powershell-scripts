# SafeTitan Trust-Listing — Multi-Tenant Deployment

Automates the [TitanHQ SafeTitan trust-listing process](https://help.safe.titanhq.com/support/solutions/articles/4000183650-microsoft-outlook-365-trust-listing) across multiple Office 365 tenants via Exchange Online PowerShell.

## What It Does

The script applies all 3 steps from the SafeTitan guide in each tenant:

| Step | Configuration | PowerShell Cmdlet |
|------|--------------|-------------------|
| **1** | Add SafeTitan IP (`204.220.164.253`) to the Anti-Spam Connection Filter allow list | `Set-HostedConnectionFilterPolicy` |
| **2** | Create transport rule: bypass spam filtering by sender IP + set `X-MS-Exchange-Organization-BypassClutter: true` | `New-TransportRule` |
| **3** | Create transport rule: bypass spam filtering by 27 SafeTitan domains + DMARC pass + sender IP, set `X-ETR` header | `New-TransportRule` |

## Prerequisites

- **PowerShell 7+**
- **ExchangeOnlineManagement module v3.2+**
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```
- **Exchange Admin or Global Admin** credentials for each tenant
- A browser profile signed into each tenant's admin account (for device code auth)

## Setup

1. Open `SafeTitan-TrustListing.ps1`
2. Edit the `$Tenants` array near the top of the script:
   ```powershell
   $Tenants = @(
       "customer1.onmicrosoft.com"
       "customer2.onmicrosoft.com"
       "customer3.onmicrosoft.com"
   )
   ```
3. Save the file

## Usage

### Dry Run (recommended first)

See what would change without touching anything:

```powershell
.\SafeTitan-TrustListing.ps1 -DryRun
```

### Normal Run

```powershell
.\SafeTitan-TrustListing.ps1
```

### Force Recreate Rules

Delete and recreate transport rules even if they already exist (useful if rules need updating):

```powershell
.\SafeTitan-TrustListing.ps1 -Force
```

## Auth Workflow

For each tenant the script will:

1. Prompt you to get ready ("Press ENTER when ready to authenticate")
2. Initiate device code auth — you'll see output like:
   ```
   To sign in, use a web browser to open the page https://microsoft.com/devicelogin
   and enter the code XXXXXXXXX to authenticate.
   ```
3. Copy that URL into a browser profile already signed in as an admin for that tenant
4. Enter the code and approve
5. The script runs the 3 steps, shows results, disconnects
6. Moves to the next tenant

## Idempotency

The script is safe to run multiple times:

- **Step 1**: Checks if the IP is already in the allow list before adding
- **Steps 2 & 3**: Checks if the transport rule already exists by name before creating
- Use `-Force` to tear down and recreate rules if you need to update them

## Logging

Each run creates a timestamped CSV log in the `logs/` folder:

```
logs/SafeTitan-TrustList-20260209-143022.csv
```

| Column | Description |
|--------|-------------|
| Timestamp | When the action occurred |
| Tenant | Which tenant domain |
| Step | Which step (Connect, Step1, Step2, Step3) |
| Status | Success, Skipped, Failed, or Info |
| Detail | Additional context or error message |

## Tenant Mismatch Warning

After connecting, the script verifies the org name matches the expected tenant. If it detects a mismatch (e.g., you authenticated with the wrong browser profile), it will warn you and ask for confirmation before proceeding.

## Updating SafeTitan Config

If TitanHQ changes their IP or adds domains, edit the constants at the top of the script:

```powershell
$SafeTitanIP = "204.220.164.253"     # Update if IP changes

$SafeTitanDomains = @(               # Add/remove domains as needed
    "e-messsage.com"
    ...
)
```

Then re-run with `-Force` to update the transport rules in all tenants.

## Files

```
SafeTitan Trust-Listing/
├── SafeTitan-TrustListing.ps1    # Main script
├── README.md                     # This file
└── logs/                         # Run logs (auto-created)
    └── SafeTitan-TrustList-*.csv
```
