#Requires -Version 7.0

<#
.SYNOPSIS
    Applies SafeTitan (TitanHQ) trust-listing configuration across multiple Office 365 tenants.

.DESCRIPTION
    Automates SafeTitan trust-listing steps across Exchange Online / Defender:
      1) Connection filter allow IP
      2) Transport rule: bypass spam + BypassClutter header
      3) Transport rule: DMARC + SafeTitan domains + sender IP
      4) Transport rule: skip junk header (X-Forefront-Antispam-Report)
      5) Transport rule: skip Safe Attachments header
      6) Transport rule: skip Safe Links header
      7) Anti-Phishing default policy trusted domains
      8) Advanced Delivery phishing simulation (domains + sender IP)

    Uses device code authentication so you can paste auth URL/code into a browser
    profile already signed into each tenant admin account.

.PARAMETER DryRun
    Show what would change without making modifications.

.PARAMETER Force
    Re-create transport rules if they exist.

.NOTES
    Requires: ExchangeOnlineManagement module (v3.2+ recommended)
#>

param (
    [switch]$DryRun,
    [switch]$Force
)

#region Constants

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

# Advanced Delivery currently allows up to 20 sending domains.
# Keep this list to 20 max (first 20 by default).
$AdvancedDeliveryDomains = $SafeTitanDomains | Select-Object -First 20

$RuleName_IPBypass          = "SafeTitan - Bypass Spam (Sender IP)"
$RuleName_DMARCBypass       = "SafeTitan - DMARC Bypass (Domains + IP)"
$RuleName_SkipJunkHeader    = "SafeTitan - Skip Junk Header"
$RuleName_SkipAttachments   = "SafeTitan - Bypass ATP Attachments"
$RuleName_SkipLinks         = "SafeTitan - Bypass ATP Link Processing"

$PhishSimPolicyName         = "SafeTitan Phishing Simulation Override"

#endregion

#region Tenant List

$Tenants = @(
    # "customer1.onmicrosoft.com"
    # "customer2.onmicrosoft.com"
)

#endregion

#region Logging

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logDir "SafeTitan-TrustList-$runTimestamp.csv"
"Timestamp,Tenant,Step,Status,Detail" | Set-Content -Path $logFile

function Write-Log {
    param(
        [string]$Tenant,
        [string]$Step,
        [ValidateSet("Success", "Skipped", "Failed", "Info")]
        [string]$Status,
        [string]$Detail = ""
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $safeDetail = $Detail -replace '"', '""'
    "`"$ts`",`"$Tenant`",`"$Step`",`"$Status`",`"$safeDetail`"" | Add-Content -Path $logFile
}

#endregion

#region Preconditions

function Assert-ExchangeModule {
    $mod = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
        Sort-Object Version -Descending | Select-Object -First 1

    if (-not $mod) {
        Write-Host "❌ ExchangeOnlineManagement module is not installed." -ForegroundColor Red
        Write-Host "Install with: Install-Module ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "✓ ExchangeOnlineManagement v$($mod.Version)" -ForegroundColor Green
}

function Test-CmdletAvailable {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

#endregion

#region Step Helpers

function Ensure-TransportRule {
    param(
        [string]$Tenant,
        [string]$StepName,
        [string]$RuleName,
        [scriptblock]$CreateAction
    )

    try {
        $existing = Get-TransportRule -Identity $RuleName -ErrorAction SilentlyContinue

        if ($existing -and -not $Force) {
            Write-Host "  ✓ Rule '$RuleName' already exists — skipping" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step $StepName -Status "Skipped" -Detail "Rule already exists"
            return $true
        }

        if ($existing -and $Force) {
            if ($DryRun) {
                Write-Host "  🔍 [DRY RUN] Would recreate '$RuleName'" -ForegroundColor Yellow
                Write-Log -Tenant $Tenant -Step $StepName -Status "Info" -Detail "DRY RUN — would recreate rule"
                return $true
            }

            Remove-TransportRule -Identity $RuleName -Confirm:$false -ErrorAction Stop
            Write-Log -Tenant $Tenant -Step $StepName -Status "Info" -Detail "Removed existing rule (-Force)"
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would create '$RuleName'" -ForegroundColor Yellow
            Write-Log -Tenant $Tenant -Step $StepName -Status "Info" -Detail "DRY RUN — would create rule"
            return $true
        }

        & $CreateAction

        Write-Host "  ✓ Created '$RuleName'" -ForegroundColor Green
        Write-Log -Tenant $Tenant -Step $StepName -Status "Success" -Detail "Rule created"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step $StepName -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

#endregion

#region Step 1-8

function Set-Step1_ConnectionFilterIP {
    param([string]$Tenant)

    Write-Host "`n  ── Step 1: Connection Filter allow IP ──" -ForegroundColor Cyan

    try {
        $policy = Get-HostedConnectionFilterPolicy -Identity Default -ErrorAction Stop
        $currentIPs = @($policy.IPAllowList)

        if ($currentIPs -contains $SafeTitanIP) {
            Write-Host "  ✓ IP already present" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Skipped" -Detail "IP already present"
            return $true
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would add $SafeTitanIP" -ForegroundColor Yellow
            Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Info" -Detail "DRY RUN — would add IP"
            return $true
        }

        Set-HostedConnectionFilterPolicy -Identity Default -IPAllowList ($currentIPs + $SafeTitanIP) -ErrorAction Stop

        Write-Host "  ✓ Added $SafeTitanIP" -ForegroundColor Green
        Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Success" -Detail "Added IP"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step "Step1-ConnectionFilter" -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

function Set-Step2_IPBypassRule {
    param([string]$Tenant)

    Write-Host "`n  ── Step 2: Rule (bypass spam + BypassClutter) ──" -ForegroundColor Cyan

    return Ensure-TransportRule -Tenant $Tenant -StepName "Step2-IPBypassRule" -RuleName $RuleName_IPBypass -CreateAction {
        New-TransportRule -Name $RuleName_IPBypass `
            -SenderIpRanges $SafeTitanIP `
            -SetSCL -1 `
            -SetHeaderName "X-MS-Exchange-Organization-BypassClutter" `
            -SetHeaderValue "true" `
            -Priority 0 `
            -ErrorAction Stop
    }
}

function Set-Step3_DMARCBypassRule {
    param([string]$Tenant)

    Write-Host "`n  ── Step 3: Rule (DMARC + domains + IP) ──" -ForegroundColor Cyan

    return Ensure-TransportRule -Tenant $Tenant -StepName "Step3-DMARCBypassRule" -RuleName $RuleName_DMARCBypass -CreateAction {
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
    }
}

function Set-Step4_SkipJunkHeaderRule {
    param([string]$Tenant)

    Write-Host "`n  ── Step 4: Rule (X-Forefront-Antispam-Report: SFV:SKI;) ──" -ForegroundColor Cyan

    return Ensure-TransportRule -Tenant $Tenant -StepName "Step4-SkipJunkHeaderRule" -RuleName $RuleName_SkipJunkHeader -CreateAction {
        New-TransportRule -Name $RuleName_SkipJunkHeader `
            -SenderIpRanges $SafeTitanIP `
            -SetSCL -1 `
            -SetHeaderName "X-Forefront-Antispam-Report" `
            -SetHeaderValue "SFV:SKI;" `
            -Priority 2 `
            -ErrorAction Stop
    }
}

function Set-Step5_AttachmentBypassRule {
    param([string]$Tenant)

    Write-Host "`n  ── Step 5: Rule (Skip Safe Attachments) ──" -ForegroundColor Cyan

    return Ensure-TransportRule -Tenant $Tenant -StepName "Step5-AttachmentBypassRule" -RuleName $RuleName_SkipAttachments -CreateAction {
        New-TransportRule -Name $RuleName_SkipAttachments `
            -SenderIpRanges $SafeTitanIP `
            -SetHeaderName "X-MS-Exchange-Organization-SkipSafeAttachmentProcessing" `
            -SetHeaderValue "1" `
            -Priority 3 `
            -ErrorAction Stop
    }
}

function Set-Step6_LinkBypassRule {
    param([string]$Tenant)

    Write-Host "`n  ── Step 6: Rule (Skip Safe Links) ──" -ForegroundColor Cyan

    return Ensure-TransportRule -Tenant $Tenant -StepName "Step6-LinkBypassRule" -RuleName $RuleName_SkipLinks -CreateAction {
        New-TransportRule -Name $RuleName_SkipLinks `
            -SenderIpRanges $SafeTitanIP `
            -SetHeaderName "X-MS-Exchange-Organization-SkipSafeLinksProcessing" `
            -SetHeaderValue "1" `
            -Priority 4 `
            -ErrorAction Stop
    }
}

function Set-Step7_AntiPhishTrustedDomains {
    param([string]$Tenant)

    Write-Host "`n  ── Step 7: Anti-Phish default trusted domains ──" -ForegroundColor Cyan

    try {
        if (-not (Test-CmdletAvailable -Name "Get-AntiPhishPolicy") -or -not (Test-CmdletAvailable -Name "Set-AntiPhishPolicy")) {
            Write-Host "  ⚠️  AntiPhish cmdlets not available in this session — skipping" -ForegroundColor Yellow
            Write-Log -Tenant $Tenant -Step "Step7-AntiPhishTrustedDomains" -Status "Skipped" -Detail "Cmdlets not available"
            return $true
        }

        $policy = Get-AntiPhishPolicy | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $policy) {
            $policy = Get-AntiPhishPolicy -Identity "Office365 AntiPhish Default" -ErrorAction SilentlyContinue
        }

        if (-not $policy) {
            throw "Could not locate default anti-phishing policy."
        }

        $existingDomains = @($policy.ExcludedDomains)
        $missingDomains = $SafeTitanDomains | Where-Object { $_ -notin $existingDomains }

        if ($missingDomains.Count -eq 0) {
            Write-Host "  ✓ All SafeTitan domains already trusted in default AntiPhish policy" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step "Step7-AntiPhishTrustedDomains" -Status "Skipped" -Detail "Domains already present"
            return $true
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would add $($missingDomains.Count) domains to '$($policy.Name)'" -ForegroundColor Yellow
            Write-Log -Tenant $Tenant -Step "Step7-AntiPhishTrustedDomains" -Status "Info" -Detail "DRY RUN — would add $($missingDomains.Count) domains"
            return $true
        }

        foreach ($d in $missingDomains) {
            Set-AntiPhishPolicy -Identity $policy.Identity -ExcludedDomains @{Add = $d} -ErrorAction Stop
        }

        Write-Host "  ✓ Added $($missingDomains.Count) trusted domains to AntiPhish default policy" -ForegroundColor Green
        Write-Log -Tenant $Tenant -Step "Step7-AntiPhishTrustedDomains" -Status "Success" -Detail "Added $($missingDomains.Count) domains"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step "Step7-AntiPhishTrustedDomains" -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

function Set-Step8_AdvancedDeliveryPhishSim {
    param([string]$Tenant)

    Write-Host "`n  ── Step 8: Advanced Delivery (Phishing Simulation) ──" -ForegroundColor Cyan

    try {
        if (-not (Test-CmdletAvailable -Name "Get-PhishSimOverridePolicy")) {
            Write-Host "  ⚠️  PhishSim cmdlets not available in EXO session. Trying IPPS session..." -ForegroundColor Yellow

            if ($DryRun) {
                Write-Host "  🔍 [DRY RUN] Would connect IPPS and configure PhishSim override policy/rule" -ForegroundColor Yellow
                Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Info" -Detail "DRY RUN — would connect IPPS and configure"
                return $true
            }

            Connect-IPPSSession -Device -ErrorAction Stop | Out-Null
        }

        $policy = Get-PhishSimOverridePolicy -Identity $PhishSimPolicyName -ErrorAction SilentlyContinue

        if (-not $policy) {
            if ($DryRun) {
                Write-Host "  🔍 [DRY RUN] Would create PhishSim policy '$PhishSimPolicyName'" -ForegroundColor Yellow
                Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Info" -Detail "DRY RUN — would create policy"
                return $true
            }

            New-PhishSimOverridePolicy -Name $PhishSimPolicyName -ErrorAction Stop | Out-Null
            $policy = Get-PhishSimOverridePolicy -Identity $PhishSimPolicyName -ErrorAction Stop
            Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Info" -Detail "Created policy '$PhishSimPolicyName'"
        }

        $rules = Get-PhishSimOverrideRule -ErrorAction SilentlyContinue
        $matchingRule = $rules | Where-Object {
            (@($_.SenderIPRanges) -contains $SafeTitanIP) -and
            (@($_.Domains) | Where-Object { $_ -in $AdvancedDeliveryDomains }).Count -ge 1
        } | Select-Object -First 1

        if ($matchingRule -and -not $Force) {
            Write-Host "  ✓ Existing Advanced Delivery override rule already found — skipping" -ForegroundColor Green
            Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Skipped" -Detail "Matching rule already exists"
            return $true
        }

        if ($matchingRule -and $Force) {
            if ($DryRun) {
                Write-Host "  🔍 [DRY RUN] Would remove/recreate existing PhishSim override rule" -ForegroundColor Yellow
                Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Info" -Detail "DRY RUN — would recreate rule"
                return $true
            }
            Remove-PhishSimOverrideRule -Identity $matchingRule.Identity -Confirm:$false -ErrorAction Stop
            Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Info" -Detail "Removed existing matching rule (-Force)"
        }

        if ($DryRun) {
            Write-Host "  🔍 [DRY RUN] Would create Advanced Delivery override rule" -ForegroundColor Yellow
            Write-Host "     Domains: $($AdvancedDeliveryDomains.Count) (limit 20), Sender IP: $SafeTitanIP" -ForegroundColor Gray
            Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Info" -Detail "DRY RUN — would create rule"
            return $true
        }

        if (Test-CmdletAvailable -Name "New-ExoPhishSimOverrideRule") {
            New-ExoPhishSimOverrideRule -Policy $PhishSimPolicyName -Domains $AdvancedDeliveryDomains -SenderIpRanges $SafeTitanIP -ErrorAction Stop | Out-Null
        }
        else {
            # Fallback name (older docs/cmdlet alias)
            New-PhishSimOverrideRule -Policy $PhishSimPolicyName -Domains $AdvancedDeliveryDomains -SenderIpRanges $SafeTitanIP -ErrorAction Stop | Out-Null
        }

        Write-Host "  ✓ Advanced Delivery phishing simulation override configured" -ForegroundColor Green
        Write-Host "  ℹ️  Used $($AdvancedDeliveryDomains.Count) domains (Advanced Delivery max is 20)" -ForegroundColor Gray
        Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Success" -Detail "Configured with $($AdvancedDeliveryDomains.Count) domains + IP"
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Tenant $Tenant -Step "Step8-AdvancedDelivery" -Status "Failed" -Detail $_.Exception.Message
        return $false
    }
}

#endregion

#region Main

function Main {

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║      SafeTitan Trust-Listing — Multi-Tenant Deployment      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    if ($DryRun) { Write-Host "`n  🔍 DRY RUN MODE" -ForegroundColor Yellow }
    if ($Force)  { Write-Host "  ⚡ FORCE MODE (recreate existing rules)" -ForegroundColor Yellow }

    Assert-ExchangeModule

    if ($Tenants.Count -eq 0) {
        Write-Host "`n❌ No tenants configured. Edit `$Tenants at top of script." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nTenants to process ($($Tenants.Count)):" -ForegroundColor Yellow
    $Tenants | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }

    $summary = @()
    $i = 0

    foreach ($tenant in $Tenants) {
        $i++

        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║  [$i/$($Tenants.Count)] Tenant: $tenant" -ForegroundColor Magenta
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

        Write-Host "  Use browser profile signed in for this tenant admin." -ForegroundColor Yellow
        Read-Host "  Press ENTER to start device auth"

        try {
            Connect-ExchangeOnline -Device -ShowBanner:$false -ErrorAction Stop
            Write-Host "  ✓ Connected to Exchange Online" -ForegroundColor Green
            Write-Log -Tenant $tenant -Step "Connect" -Status "Success"
        }
        catch {
            Write-Host "  ✗ Connect failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log -Tenant $tenant -Step "Connect" -Status "Failed" -Detail $_.Exception.Message
            $summary += [PSCustomObject]@{ Tenant = $tenant; S1="-"; S2="-"; S3="-"; S4="-"; S5="-"; S6="-"; S7="-"; S8="-"; Overall="CONNECT FAILED" }
            continue
        }

        $s1 = Set-Step1_ConnectionFilterIP -Tenant $tenant
        $s2 = Set-Step2_IPBypassRule -Tenant $tenant
        $s3 = Set-Step3_DMARCBypassRule -Tenant $tenant
        $s4 = Set-Step4_SkipJunkHeaderRule -Tenant $tenant
        $s5 = Set-Step5_AttachmentBypassRule -Tenant $tenant
        $s6 = Set-Step6_LinkBypassRule -Tenant $tenant
        $s7 = Set-Step7_AntiPhishTrustedDomains -Tenant $tenant
        $s8 = Set-Step8_AdvancedDeliveryPhishSim -Tenant $tenant

        $okCount = @($s1,$s2,$s3,$s4,$s5,$s6,$s7,$s8 | Where-Object { $_ -eq $true }).Count
        $overall = if ($okCount -eq 8) { "ALL OK" } elseif ($okCount -eq 0) { "FAILED" } else { "PARTIAL" }

        $summary += [PSCustomObject]@{
            Tenant  = $tenant
            S1      = $(if ($s1) {"✓"} else {"✗"})
            S2      = $(if ($s2) {"✓"} else {"✗"})
            S3      = $(if ($s3) {"✓"} else {"✗"})
            S4      = $(if ($s4) {"✓"} else {"✗"})
            S5      = $(if ($s5) {"✓"} else {"✗"})
            S6      = $(if ($s6) {"✓"} else {"✗"})
            S7      = $(if ($s7) {"✓"} else {"✗"})
            S8      = $(if ($s8) {"✓"} else {"✗"})
            Overall = $overall
        }

        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        try { Disconnect-IPPSSession -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

        Write-Host "`n  ✓ Tenant complete: $tenant" -ForegroundColor Green
    }

    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         SUMMARY                             ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Host ("  {0,-32} {1,2} {2,2} {3,2} {4,2} {5,2} {6,2} {7,2} {8,2}   {9}" -f "Tenant","1","2","3","4","5","6","7","8","Overall") -ForegroundColor White
    Write-Host ("  {0,-32} {1,2} {2,2} {3,2} {4,2} {5,2} {6,2} {7,2} {8,2}   {9}" -f "------","-","-","-","-","-","-","-","-","-------") -ForegroundColor Gray

    foreach ($row in $summary) {
        $color = switch ($row.Overall) {
            "ALL OK" { "Green" }
            "PARTIAL" { "Yellow" }
            default { "Red" }
        }

        Write-Host ("  {0,-32} {1,2} {2,2} {3,2} {4,2} {5,2} {6,2} {7,2} {8,2}   {9}" -f $row.Tenant,$row.S1,$row.S2,$row.S3,$row.S4,$row.S5,$row.S6,$row.S7,$row.S8,$row.Overall) -ForegroundColor $color
    }

    Write-Host "`n  Log file: $logFile" -ForegroundColor Gray
    Write-Host "  Steps: 1=ConnFilter, 2=BypassClutter, 3=DMARC, 4=SkipJunk, 5=SkipAttach, 6=SkipLinks, 7=AntiPhish, 8=AdvancedDelivery" -ForegroundColor Gray
}

#endregion

try {
    Main
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue 2>$null
    try { Disconnect-IPPSSession -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
}
