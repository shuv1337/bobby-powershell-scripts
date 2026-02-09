#Requires -Version 7.0

<#
.SYNOPSIS
    Applies SafeTitan (TitanHQ) trust-listing configuration across multiple Office 365 tenants.

.DESCRIPTION
    Automates the 3-step SafeTitan trust-listing process from the TitanHQ guide:
      Step 1: Add SafeTitan IP to Connection Filter Allow List (Anti-Spam)
      Step 2: Create transport rule — bypass spam by sender IP + bypass Clutter
      Step 3: Create transport rule — bypass spam by DMARC + domains + sender IP

    Uses device code authentication so you can paste the auth URL into a browser
    profile that is already logged into each tenant's admin account.

    The script is fully idempotent — it checks for existing configuration before
    making changes and skips anything already in place.

    Reference: https://help.safe.titanhq.com/support/solutions/articles/4000183650

.PARAMETER DryRun
    Show what would be changed without making any modifications.

.PARAMETER Force
    Re-create transport rules even if they already exist (deletes and recreates).

.NOTES
    Author:   Bobby / Latitudes Team
    Requires: ExchangeOnlineManagement module v3.2+
              Global Admin or Exchange Admin role on each tenant
#>

param (
    [switch]$DryRun,
    [switch]$Force
)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                            CONFIGURATION                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region SafeTitan Constants — update if TitanHQ changes IPs or domains

$SafeTitanIP = "204.220.164.253"

$SafeTitanDomains = @(
    "e-messsage.com"
    "emesssages.com"
    "e-citrix.com"
    "ecompliants.com"
    "e-compliants.com"
    "e-faax.com"
    "eonline-shopping.com"
    "e-outlook-online.com"
    "e-owa.com"
    "evpnn.com"
    "e-vpnn.com"
    "orders-processed.com"
    "storage-limit.com"
    "docusine.com"
    "barclaysbanksonline.co.uk"
    "docs-google.com"
    "it-admingroup.com"
    "it-companyadmin.com"
    "it-securegroup.com"
    "it-securemail.com"
    "bitliy.co"
    "order-processed.com"
    "corp-benefits-online.com"
    "advanced-documents.com"
    "delivery-details.com"
    "it-communications.com"
    "keeper-secure.com"
)

# Transport rule names — used for idempotency checks
$RuleName_IPBypass    = "SafeTitan - Bypass Spam (Sender IP)"
$RuleName_DMARCBypass = "SafeTitan - DMARC Bypass (Domains + IP)"

#endregion

#region Tenant List — add/remove customer tenant domains here

$Tenants = @(
    # "customer1.onmicrosoft.com"
    # "customer2.onmicrosoft.com"
    # "customer3.onmicrosoft.com"
)

#endregion

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              LOGGING                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region Logging Setup

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logDir "SafeTitan-TrustList-$runTimestamp.csv"

# Seed log file with header row only
"Timestamp,Tenant,Step,Status,Detail" | Set-Content -Path $logFile

function Write-Log {
    param (
        [string]$Tenant,
        [string]$Step,
        [ValidateSet("Success", "Skipped", "Failed", "Info")]
        [string]$Status,
        [string]$Detail = ""
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Escape quotes in detail for CSV safety
    $safeDetail = $Detail -replace '"', '""'
    "`"$ts`",`"$Tenant`",`"$Step`",`"$Status`",`"$safeDetail`"" | Add-Content -Path $logFile
}

#endregion

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         MODULE PREFLIGHT                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region Module Check

function Assert-ExchangeModule {
    $mod = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
        Sort-Object Version -Descending | Select-Object -First 1

    if (-not $mod) {
        Write-Host "❌ ExchangeOnlineManagement module is not installed." -ForegroundColor Red
        Write-Host "   Install it with:  Install-Module ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }

    if ($mod.Version -lt [Version]"3.2.0") {
        Write-Host "⚠️  ExchangeOnlineManagement v$($mod.Version) found — v3.2+ recommended for -Device auth." -ForegroundColor Yellow
        Write-Host "   Update with:  Update-Module ExchangeOnlineManagement -Force" -ForegroundColor Yellow
    }
    else {
        Write-Host "✓ ExchangeOnlineManagement v$($mod.Version)" -ForegroundColor Green
    }
}

#endregion

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     STEP 1 — CONNECTION FILTER                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region Step 1

function Set-Step1_ConnectionFilterIP {
    param ([string]$Tenant)

    Write-Host "`n  ── Step 1: Connection Filter IP Allow List ──" -ForegroundColor Cyan

    try {
        $policy = Get-HostedConnectionFilterPolicy -Identity Default -ErrorAction Stop
        $currentIPs = @($policy.IPAllowList)

        if ($currentIPs -contains $SafeTitanIP) {
            Write-Host "  ✓ IP $SafeTitanIP already in allow list — skipping" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Skipped" -Detail "IP already present"
            return $true
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would add $SafeTitanIP to allow list (current: $($currentIPs -join ', '))" -ForegroundColor Yellow
            Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Info" -Detail "DRY RUN — would add IP"
            return $true
        }

        $newIPs = $currentIPs + $SafeTitanIP
        Set-HostedConnectionFilterPolicy -Identity Default -IPAllowList $newIPs -ErrorAction Stop

        Write-Host "  ✓ Added $SafeTitanIP to Connection Filter allow list" -ForegroundColor Green
        Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Success" -Detail "Added IP $SafeTitanIP"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

#endregion

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║           STEP 2 — TRANSPORT RULE: BYPASS SPAM (SENDER IP)                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region Step 2

function Set-Step2_IPBypassRule {
    param ([string]$Tenant)

    Write-Host "`n  ── Step 2: Transport Rule — Bypass Spam (Sender IP) ──" -ForegroundColor Cyan

    try {
        $existing = Get-TransportRule -Identity $RuleName_IPBypass -ErrorAction SilentlyContinue

        if ($existing -and -not $Force) {
            Write-Host "  ✓ Rule '$RuleName_IPBypass' already exists — skipping (use -Force to recreate)" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step "Step2-IPBypassRule" -Status "Skipped" -Detail "Rule already exists"
            return $true
        }

        if ($existing -and $Force) {
            if ($DryRun) {
                Write-Host "  🔍 [DRY RUN] Would delete and recreate rule '$RuleName_IPBypass'" -ForegroundColor Yellow
                Write-Log -Tenant $Tenant -Step "Step2-IPBypassRule" -Status "Info" -Detail "DRY RUN — would recreate rule"
                return $true
            }
            Write-Host "  🔄 -Force: Removing existing rule before recreating..." -ForegroundColor Yellow
            Remove-TransportRule -Identity $RuleName_IPBypass -Confirm:$false -ErrorAction Stop
            Write-Log -Tenant $Tenant -Step "Step2-IPBypassRule" -Status "Info" -Detail "Removed existing rule (-Force)"
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would create rule '$RuleName_IPBypass'" -ForegroundColor Yellow
            Write-Host "     Sender IP: $SafeTitanIP | SCL: -1 | BypassClutter: true" -ForegroundColor Gray
            Write-Log -Tenant $Tenant -Step "Step2-IPBypassRule" -Status "Info" -Detail "DRY RUN — would create rule"
            return $true
        }

        New-TransportRule -Name $RuleName_IPBypass `
            -SenderIpRanges $SafeTitanIP `
            -SetSCL -1 `
            -SetHeaderName "X-MS-Exchange-Organization-BypassClutter" `
            -SetHeaderValue "true" `
            -Priority 0 `
            -ErrorAction Stop

        Write-Host "  ✓ Created rule '$RuleName_IPBypass'" -ForegroundColor Green
        Write-Log -Tenant $Tenant -Step "Step2-IPBypassRule" -Status "Success" -Detail "Rule created"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step "Step2-IPBypassRule" -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

#endregion

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║        STEP 3 — TRANSPORT RULE: DMARC BYPASS (DOMAINS + IP)               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region Step 3

function Set-Step3_DMARCBypassRule {
    param ([string]$Tenant)

    Write-Host "`n  ── Step 3: Transport Rule — DMARC Bypass (Domains + IP) ──" -ForegroundColor Cyan

    try {
        $existing = Get-TransportRule -Identity $RuleName_DMARCBypass -ErrorAction SilentlyContinue

        if ($existing -and -not $Force) {
            Write-Host "  ✓ Rule '$RuleName_DMARCBypass' already exists — skipping (use -Force to recreate)" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step "Step3-DMARCBypassRule" -Status "Skipped" -Detail "Rule already exists"
            return $true
        }

        if ($existing -and $Force) {
            if ($DryRun) {
                Write-Host "  🔍 [DRY RUN] Would delete and recreate rule '$RuleName_DMARCBypass'" -ForegroundColor Yellow
                Write-Log -Tenant $Tenant -Step "Step3-DMARCBypassRule" -Status "Info" -Detail "DRY RUN — would recreate rule"
                return $true
            }
            Write-Host "  🔄 -Force: Removing existing rule before recreating..." -ForegroundColor Yellow
            Remove-TransportRule -Identity $RuleName_DMARCBypass -Confirm:$false -ErrorAction Stop
            Write-Log -Tenant $Tenant -Step "Step3-DMARCBypassRule" -Status "Info" -Detail "Removed existing rule (-Force)"
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would create rule '$RuleName_DMARCBypass'" -ForegroundColor Yellow
            Write-Host "     Domains: $($SafeTitanDomains.Count) | Sender IP: $SafeTitanIP" -ForegroundColor Gray
            Write-Host "     DMARC header match: dmarc=pass, dmarc=bestguesspass" -ForegroundColor Gray
            Write-Host "     SCL: -1 | X-ETR header set" -ForegroundColor Gray
            Write-Log -Tenant $Tenant -Step "Step3-DMARCBypassRule" -Status "Info" -Detail "DRY RUN — would create rule"
            return $true
        }

        New-TransportRule -Name $RuleName_DMARCBypass `
            -SenderDomainIs $SafeTitanDomains `
            -FromScope "NotInOrganization" `
            -HeaderContainsMessageHeader "Authentication-Results" `
            -HeaderContainsWords @("dmarc=pass", "dmarc=bestguesspass") `
            -SenderIpRanges $SafeTitanIP `
            -SetSCL -1 `
            -SetHeaderName "X-ETR" `
            -SetHeaderValue "Bypass spam filtering for authenticated SafeTitan domains" `
            -Priority 1 `
            -ErrorAction Stop

        Write-Host "  ✓ Created rule '$RuleName_DMARCBypass'" -ForegroundColor Green
        Write-Log -Tenant $Tenant -Step "Step3-DMARCBypassRule" -Status "Success" -Detail "Rule created with $($SafeTitanDomains.Count) domains"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step "Step3-DMARCBypassRule" -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

#endregion

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                             MAIN                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#region Main

function Main {

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║      SafeTitan Trust-Listing — Multi-Tenant Deployment      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "`n  🔍 DRY RUN MODE — no changes will be made" -ForegroundColor Yellow
    }
    if ($Force) {
        Write-Host "  ⚡ FORCE MODE — existing rules will be deleted and recreated" -ForegroundColor Yellow
    }

    Write-Host ""
    Assert-ExchangeModule

    # ── Validate tenant list ──
    if ($Tenants.Count -eq 0) {
        Write-Host "`n❌ No tenants configured." -ForegroundColor Red
        Write-Host "   Edit the `$Tenants array at the top of this script to add your tenant domains." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "`nTenants to process ($($Tenants.Count)):" -ForegroundColor Yellow
    $Tenants | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }

    # ── Auth workflow hint ──
    Write-Host "`n┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Gray
    Write-Host "│  AUTH WORKFLOW                                               │" -ForegroundColor Gray
    Write-Host "│                                                              │" -ForegroundColor Gray
    Write-Host "│  For each tenant the script will show a device login URL     │" -ForegroundColor Gray
    Write-Host "│  and a one-time code. Copy the URL, paste it into a browser  │" -ForegroundColor Gray
    Write-Host "│  profile already signed in as an admin for that tenant,      │" -ForegroundColor Gray
    Write-Host "│  enter the code, and approve.                                │" -ForegroundColor Gray
    Write-Host "│                                                              │" -ForegroundColor Gray
    Write-Host "│  URL:  https://microsoft.com/devicelogin                     │" -ForegroundColor Gray
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Gray

    $summary = @()
    $tenantIndex = 0

    foreach ($tenant in $Tenants) {
        $tenantIndex++

        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║  [$tenantIndex/$($Tenants.Count)] Tenant: $tenant" -ForegroundColor Magenta
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

        # ── Prompt before auth so the user can switch browser profiles ──
        Write-Host ""
        Write-Host "  ➡️  Make sure you have a browser profile open that is signed in" -ForegroundColor Yellow
        Write-Host "     as an Exchange/Global Admin for: $tenant" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "  Press ENTER when ready to authenticate"

        # ── Connect with device code auth ──
        Write-Host "  Initiating device code authentication..." -ForegroundColor Cyan
        Write-Host "  Copy the URL below and paste it into that browser profile:" -ForegroundColor Cyan
        Write-Host ""

        try {
            Connect-ExchangeOnline -Device -ShowBanner:$false -ErrorAction Stop
            Write-Host ""
            Write-Host "  ✓ Connected to Exchange Online" -ForegroundColor Green
            Write-Log -Tenant $tenant -Step "Connect" -Status "Success"
        }
        catch {
            Write-Host "  ✗ Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log -Tenant $tenant -Step "Connect" -Status "Failed" -Detail $_.Exception.Message
            $summary += [PSCustomObject]@{
                Tenant  = $tenant
                Step1   = "—"
                Step2   = "—"
                Step3   = "—"
                Overall = "CONNECT FAILED"
            }
            continue
        }

        # ── Verify we're in the right tenant ──
        try {
            $orgConfig = Get-OrganizationConfig -ErrorAction Stop
            $orgName = $orgConfig.DisplayName
            $orgDomain = $orgConfig.Name
            Write-Host "  ✓ Verified org: $orgName ($orgDomain)" -ForegroundColor Green
            Write-Log -Tenant $tenant -Step "Verify" -Status "Info" -Detail "Org: $orgName ($orgDomain)"

            # Sanity check — warn if the org domain doesn't match the expected tenant
            if ($orgDomain -notlike "*$($tenant.Split('.')[0])*") {
                Write-Host ""
                Write-Host "  ⚠️  WARNING: Connected org '$orgDomain' may not match expected tenant '$tenant'" -ForegroundColor Red
                Write-Host "  ⚠️  You may have authenticated with the wrong account." -ForegroundColor Red
                Write-Log -Tenant $tenant -Step "Verify" -Status "Info" -Detail "MISMATCH WARNING: org=$orgDomain expected=$tenant"
                $proceed = Read-Host "  Continue anyway? (Y/N)"
                if ($proceed -ne "Y" -and $proceed -ne "y") {
                    Write-Host "  Skipping tenant." -ForegroundColor Yellow
                    Write-Log -Tenant $tenant -Step "Verify" -Status "Failed" -Detail "User aborted — tenant mismatch"
                    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
                    $summary += [PSCustomObject]@{
                        Tenant  = $tenant
                        Step1   = "—"
                        Step2   = "—"
                        Step3   = "—"
                        Overall = "SKIPPED (MISMATCH)"
                    }
                    continue
                }
            }
        }
        catch {
            Write-Host "  ⚠️  Could not verify tenant identity — proceeding anyway" -ForegroundColor Yellow
            Write-Log -Tenant $tenant -Step "Verify" -Status "Info" -Detail "Could not get org config: $($_.Exception.Message)"
        }

        # ── Execute the 3 trust-listing steps ──
        $s1 = Set-Step1_ConnectionFilterIP   -Tenant $tenant
        $s2 = Set-Step2_IPBypassRule         -Tenant $tenant
        $s3 = Set-Step3_DMARCBypassRule      -Tenant $tenant

        $overall = if ($s1 -and $s2 -and $s3) { "ALL OK" } else { "PARTIAL" }

        $summary += [PSCustomObject]@{
            Tenant  = $tenant
            Step1   = $(if ($s1) { "✓" } else { "✗" })
            Step2   = $(if ($s2) { "✓" } else { "✗" })
            Step3   = $(if ($s3) { "✓" } else { "✗" })
            Overall = $overall
        }

        # ── Disconnect before next tenant ──
        try {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "`n  ✓ Disconnected from $tenant" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠️  Disconnect warning: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # ── Final Summary ──
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     DEPLOYMENT SUMMARY                      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Column headers
    Write-Host ("  {0,-40} {1,-7} {2,-7} {3,-7} {4}" -f "Tenant", "Step1", "Step2", "Step3", "Overall") -ForegroundColor White
    Write-Host ("  {0,-40} {1,-7} {2,-7} {3,-7} {4}" -f "──────", "─────", "─────", "─────", "───────") -ForegroundColor Gray

    foreach ($row in $summary) {
        $color = switch ($row.Overall) {
            "ALL OK"  { "Green"  }
            "PARTIAL" { "Yellow" }
            default   { "Red"    }
        }
        Write-Host ("  {0,-40} {1,-7} {2,-7} {3,-7} {4}" -f $row.Tenant, $row.Step1, $row.Step2, $row.Step3, $row.Overall) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Log file: $logFile" -ForegroundColor Gray
    Write-Host ""

    # ── Legend ──
    Write-Host "  Step 1 = Connection Filter IP Allow List" -ForegroundColor Gray
    Write-Host "  Step 2 = Transport Rule: Bypass Spam (Sender IP + BypassClutter)" -ForegroundColor Gray
    Write-Host "  Step 3 = Transport Rule: DMARC Bypass (27 domains + IP + Auth-Results)" -ForegroundColor Gray
    Write-Host ""
}

#endregion

# ── Entry Point ──
try {
    Main
}
finally {
    # Ensure we always disconnect, even on unexpected errors
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue 2>$null
}
