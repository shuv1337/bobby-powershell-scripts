# SafeTitan Trust-Listing — Multi-Tenant Deployment

Automates SafeTitan/TitanHQ allowlisting steps across multiple Office 365 tenants using Exchange Online PowerShell + device code auth.

## Sources Implemented

- https://help.safe.titanhq.com/support/solutions/articles/4000183650-microsoft-outlook-365-trust-listing
- https://help.safe.titanhq.com/support/solutions/articles/4000183597-office-365-mail-flow-rules
- https://help.safe.titanhq.com/support/solutions/articles/4000183587-office-365-advanced-threat-protection-anti-phishing-policy
- https://help.safe.titanhq.com/support/solutions/articles/4000183627-microsoft-o365-advanced-delivery-phishing-simulation

## What the Script Configures

| Step | Area | What it applies |
|---|---|---|
| 1 | Connection Filter | Add sender IP `204.220.164.253` to allow list |
| 2 | Mail Flow Rule | Bypass spam (SCL -1) + set `X-MS-Exchange-Organization-BypassClutter: true` |
| 3 | Mail Flow Rule | DMARC + SafeTitan domains + sender IP + set `X-ETR` |
| 4 | Mail Flow Rule | Set `X-Forefront-Antispam-Report: SFV:SKI;` |
| 5 | Mail Flow Rule | Set `X-MS-Exchange-Organization-SkipSafeAttachmentProcessing: 1` |
| 6 | Mail Flow Rule | Set `X-MS-Exchange-Organization-SkipSafeLinksProcessing: 1` |
| 7 | Anti-Phishing Policy | Add SafeTitan domains to default AntiPhish trusted domains (`ExcludedDomains`) |
| 8 | Advanced Delivery | Configure phishing simulation override with domains + sender IP |

## Important Limits / Notes

- **Advanced Delivery domain limit is 20.**
  - Script uses the first 20 domains from `$SafeTitanDomains` by default.
  - Adjust `$AdvancedDeliveryDomains` in script if you want a different 20.
- Step 8 may need **IPPSSession** cmdlets depending on tenant/module behavior.
- Script is idempotent:
  - Existing values/rules are skipped
  - Use `-Force` to recreate transport rules / matching advanced-delivery rule

## Prerequisites

- PowerShell 7+
- ExchangeOnlineManagement module
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```
- Exchange Admin or Global Admin access in each tenant
- Browser profiles already signed into each tenant admin account

## Setup

Edit tenant list in `SafeTitan-TrustListing.ps1`:

```powershell
$Tenants = @(
  "customer1.onmicrosoft.com"
  "customer2.onmicrosoft.com"
)
```

## Usage

Dry-run first:

```powershell
.\SafeTitan-TrustListing.ps1 -DryRun
```

Normal:

```powershell
.\SafeTitan-TrustListing.ps1
```

Force recreate:

```powershell
.\SafeTitan-TrustListing.ps1 -Force
```

## Device Auth Workflow

For each tenant:

1. Script pauses and asks you to press Enter.
2. `Connect-ExchangeOnline -Device` prints `https://microsoft.com/devicelogin` + code.
3. Paste URL in the browser profile for that tenant.
4. Enter code and approve.
5. Script runs all steps, logs results, disconnects, moves to next tenant.

## Logging

Each run writes a timestamped CSV in `logs/`:

```
logs/SafeTitan-TrustList-YYYYMMDD-HHMMSS.csv
```

Columns:

- `Timestamp`
- `Tenant`
- `Step`
- `Status` (`Success`, `Skipped`, `Failed`, `Info`)
- `Detail`
