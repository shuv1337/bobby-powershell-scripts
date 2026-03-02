# MS365Entra-Termination.ps1 - Detailed Code Review

**Script:** `MS365Entra-Termination.ps1`
**Author:** Bobby
**Review Date:** January 2026
**PowerShell Version Required:** 7.0+
**Lines of Code:** 1,095

---

## Executive Summary

This script automates employee offboarding in **cloud-only Microsoft Entra ID** (formerly Azure AD) environments. It performs security lockout actions, exports user data for compliance, converts mailboxes to shared, and configures delegate access—all through a single CSV-driven workflow.

**Classification:** Production-ready administrative tool
**Risk Level:** Low (standard IT operations)
**Recommended Use:** Cloud-only M365 tenants without on-premises AD

---

## Table of Contents

1. [Workflow Overview](#workflow-overview)
2. [Input Requirements](#input-requirements)
3. [Actions Performed](#actions-performed)
4. [Function Reference](#function-reference)
5. [Permissions Required](#permissions-required)
6. [Error Handling](#error-handling)
7. [Output Files](#output-files)
8. [Security Analysis](#security-analysis)
9. [Limitations](#limitations)
10. [Usage Examples](#usage-examples)

---

## Workflow Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                         INITIALIZATION                              │
│  • Verify/install required PowerShell modules                       │
│  • Connect to Microsoft Graph (interactive authentication)          │
│  • Connect to Exchange Online                                       │
│  • Load and validate Term_User.csv                                  │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                      PRE-TERMINATION EXPORT                         │
│  • Export all group memberships (categorized by type)               │
│  • Export license assignments with human-readable names             │
│  • Save to: exports/{UPN}_offboarding-{MM-dd-yyyy}.csv             │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                      TERMINATION SEQUENCE                           │
│  1. Remove admin roles (if any)                                     │
│  2. Block sign-in (AccountEnabled = false)                          │
│  3. Revoke all active sessions                                      │
│  4. Rename display name → "{Name} - Email Archive"                  │
│  5. Hide from Global Address List                                   │
│  6. Set Out of Office auto-reply (if provided)                      │
│  7. Convert mailbox to Shared type                                  │
│  8. Add delegate(s) with Full Access                                │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                           CLEANUP                                   │
│  • Display termination results summary                              │
│  • Disconnect from Microsoft Graph                                  │
│  • Disconnect from Exchange Online                                  │
└────────────────────────────────────────────────────────────────────┘
```

---

## Input Requirements

### CSV File: `Term_User.csv`

The script expects a CSV file in the same directory with the following structure:

| Column | Required | Description |
|--------|----------|-------------|
| `Term_User_UPN` | Yes | User Principal Name of the terminated employee |
| `Delegate1` | Yes* | Primary delegate email (can be empty) |
| `Delegate2` | No | Secondary delegate email |
| `Delegate3` | No | Tertiary delegate email |
| `OOO` | Yes* | Out of Office message text (can be empty) |

*Column must exist but value can be blank

**Example CSV:**
```csv
Term_User_UPN,Delegate1,Delegate2,Delegate3,OOO
john.doe@contoso.com,jane.smith@contoso.com,bob.wilson@contoso.com,,"John is no longer with the company. Please contact Jane Smith at jane.smith@contoso.com for assistance."
alice.jones@contoso.com,manager@contoso.com,,,"Alice has left the organization. Contact IT for mailbox access requests."
```

---

## Actions Performed

### 1. Block Sign-In
- **Method:** `Update-MgUser -AccountEnabled $false`
- **Pre-check:** Removes admin roles first to avoid permission errors
- **Idempotent:** Skips if already disabled

### 2. Revoke Sessions
- **Method:** `Revoke-MgUserSignInSession`
- **Effect:** Invalidates all refresh tokens immediately
- **Result:** User signed out of all devices and applications

### 3. Rename Display Name
- **Format:** `{Original Name} - Email Archive`
- **Idempotent:** Skips if suffix already present
- **Purpose:** Visual indicator in address book/admin consoles

### 4. Hide from GAL
- **Method:** `Set-Mailbox -HiddenFromAddressListsEnabled $true`
- **Effect:** User no longer appears in Outlook address book
- **Note:** Uses Exchange Online (not Graph API)

### 5. Set Out of Office
- **Method:** `Set-MailboxAutoReplyConfiguration`
- **Scope:** Both internal and external messages
- **State:** Enabled indefinitely
- **Conditional:** Only set if OOO column has content

### 6. Convert to Shared Mailbox
- **Method:** `Set-Mailbox -Type Shared`
- **Benefit:** Shared mailboxes under 50GB don't require a license
- **Preserves:** All emails, folders, and settings

### 7. Add Delegates
- **Method:** `Add-MailboxPermission -AccessRights FullAccess`
- **AutoMapping:** Enabled (mailbox appears in Outlook automatically)
- **Limit:** Up to 3 delegates per terminated user

---

## Function Reference

### Core Functions

| Function | Lines | Purpose |
|----------|-------|---------|
| `Block-UserSignIn` | 264-320 | Disable account and remove admin roles |
| `Revoke-UserSessions` | 212-235 | Invalidate all active sessions |
| `Hide-UserFromGAL` | 322-342 | Hide mailbox from address lists |
| `Convert-ToSharedMailbox` | 344-364 | Change mailbox type to Shared |
| `Rename-UserDisplayName` | 366-397 | Append "- Email Archive" suffix |
| `Export-UserMemberships` | 399-479 | Export group memberships to CSV |
| `Export-UserLicenses` | 611-693 | Export license assignments |
| `Add-MailboxDelegates` | 775-834 | Grant Full Access to delegates |
| `Set-OutOfOfficeMessage` | 836-859 | Configure auto-reply |

### Support Functions

| Function | Lines | Purpose |
|----------|-------|---------|
| `Connect-ToGraph` | 145-168 | Establish Microsoft Graph connection |
| `Connect-ToExchangeOnline` | 170-188 | Establish Exchange Online connection |
| `Disconnect-FromGraph` | 190-199 | Clean disconnection from Graph |
| `Disconnect-FromExchangeOnline` | 201-210 | Clean disconnection from EXO |
| `Write-Log` | 36-80 | CSV-based error logging |
| `Install-RequiredModules` | 93-120 | Auto-install missing modules |
| `Read-OffboardingCSV` | 697-743 | Load and validate CSV input |
| `Create-CSVTemplate` | 745-771 | Generate example CSV file |
| `Get-LicenseFriendlyName` | 484-609 | SKU to readable name mapping |

### Orchestration

| Function | Lines | Purpose |
|----------|-------|---------|
| `Start-UserTermination` | 863-974 | Main termination workflow |
| `Main` | 976-1078 | Script entry point and CLI handling |

---

## Permissions Required

### Microsoft Graph API Scopes

```powershell
Connect-MgGraph -Scopes @(
    "User.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All",
    "Mail.ReadWrite",
    "MailboxSettings.ReadWrite",
    "User.ManageIdentities.All",
    "User.Read.All"
)
```

| Scope | Usage |
|-------|-------|
| `User.ReadWrite.All` | Read user properties, disable accounts |
| `Group.ReadWrite.All` | Read group memberships |
| `Directory.ReadWrite.All` | Remove admin role assignments |
| `Mail.ReadWrite` | Mailbox operations |
| `MailboxSettings.ReadWrite` | Out of Office configuration |
| `User.ManageIdentities.All` | Identity management operations |

### Exchange Online Roles

- **Minimum:** Exchange Administrator
- **Recommended:** Global Administrator (for admin role removal)

### Azure AD Roles

- **Minimum:** User Administrator + Exchange Administrator
- **Recommended:** Global Administrator

---

## Error Handling

### Logging System

All errors are logged to: `logs/TerminationErrors.csv`

**Log Format:**
| Field | Description |
|-------|-------------|
| Timestamp | ISO 8601 format |
| UserPrincipalName | Target user |
| Function | Function where error occurred |
| ErrorType | Error, Warning, or Info |
| ErrorMessage | Human-readable message |
| ErrorDetails | Exception details |

### Resilience Features

| Feature | Implementation |
|---------|---------------|
| Try/Catch blocks | All functions wrapped |
| Partial failure handling | Continues to next user on error |
| Connection validation | Tests connection before operations |
| Idempotent operations | Safe to re-run |
| Finally block | Ensures disconnection on exit |

### Exit Codes

The script does not use explicit exit codes. Check console output and log files for status.

---

## Output Files

### Export Directory: `exports/`

**Membership Export:**
- **Filename:** `{UPN}_offboarding-{MM-dd-yyyy}.csv`
- **Contains:** Group memberships categorized by type

```csv
"Group Type","Group Name"
"Microsoft 365","Marketing Team"
"Security","VPN Users"
"Distribution","All Staff"
"Mail-Enabled Security","Finance Approvers"
```

**License data** is appended to the same file with a section header.

### Log Directory: `logs/`

**Error Log:**
- **Filename:** `TerminationErrors.csv`
- **Append mode:** New errors added to existing file

---

## Security Analysis

### Strengths

| Aspect | Implementation |
|--------|---------------|
| Authentication | Interactive only, no stored credentials |
| Session security | Immediate revocation of all tokens |
| Privilege handling | Admin roles removed before disabling |
| Audit trail | Pre-change export for compliance |
| Cleanup | Guaranteed disconnection via finally block |

### Security Sequence

```
1. Remove admin roles     ← Prevents privilege retention
2. Disable account        ← Blocks new authentications
3. Revoke sessions        ← Terminates active sessions
4. Hide from GAL          ← Reduces attack surface visibility
```

### Not Implemented

| Feature | Risk | Mitigation |
|---------|------|------------|
| Password reset | Low | Account is disabled |
| MFA reset | Low | Account is disabled |
| License removal | None | Shared mailbox may need license if >50GB |
| Group removal | Low | Groups exported for audit |

---

## Limitations

### Compared to Hybrid/Retired Scripts

| Feature | This Script | Retired Hybrid Scripts |
|---------|-------------|------------------------|
| Password reset | No | Yes (21-char random) |
| License removal | No | Smart removal based on size |
| Group removal | No | Full removal |
| Email forwarding | No | Yes |
| SendAs permissions | No | Yes |
| Home directory move | N/A | Yes (on-prem) |
| AD account disable | N/A | Yes |

### Technical Limitations

1. **Cloud-only:** No on-premises Active Directory support
2. **Single tenant:** Cannot process users across tenants
3. **No retry logic:** Failed API calls are logged but not retried
4. **No parallelization:** Users processed sequentially
5. **Interactive auth:** Cannot run unattended/scheduled

### Mailbox Considerations

- Shared mailboxes over 50GB still require a license
- Archive mailboxes are not addressed
- Litigation hold status is not checked or modified

---

## Usage Examples

### Standard Execution

```powershell
# Ensure Term_User.csv exists in script directory
.\MS365Entra-Termination.ps1
```

### Create CSV Template

```powershell
.\MS365Entra-Termination.ps1 -CreateTemplate
# Opens template in default CSV editor
```

### Test Sign-In Blocking

```powershell
.\MS365Entra-Termination.ps1 -TestBlock
# Prompts for UPN and tests blocking only
```

### Programmatic Usage

```powershell
# Import functions for custom workflows
. .\MS365Entra-Termination.ps1

# Connect manually
Connect-ToGraph
Connect-ToExchangeOnline

# Process single user with custom options
Start-UserTermination `
    -UserPrincipalName "user@domain.com" `
    -Delegate1 "manager@domain.com" `
    -OutOfOfficeMessage "Contact IT for assistance" `
    -SkipConvertToShared  # Keep as user mailbox
```

---

## Module Dependencies

### Required Modules

| Module | Version | Purpose |
|--------|---------|---------|
| `Microsoft.Graph.Authentication` | Latest | Graph API authentication |
| `Microsoft.Graph.Users` | Latest | User operations |
| `Microsoft.Graph.Users.Actions` | Latest | Session revocation |
| `Microsoft.Graph.Identity.DirectoryManagement` | Latest | Role management |
| `Microsoft.Graph.Groups` | Latest | Group membership queries |
| `ExchangeOnlineManagement` | Latest | Mailbox operations |

### Auto-Installation

The script automatically installs missing modules to `CurrentUser` scope:

```powershell
Install-Module -Name $module -Scope CurrentUser -Force
```

---

## Recommendations

### Before Production Use

1. **Test in non-production tenant** with test accounts
2. **Verify admin role requirements** match your security model
3. **Review license strategy** for shared mailbox retention
4. **Configure log retention** for compliance requirements

### Potential Enhancements

1. Add password reset functionality
2. Implement license removal with size-based logic
3. Add support for certificate-based authentication
4. Implement retry logic for transient failures
5. Add email notification to IT/HR on completion

---

## Conclusion

`MS365Entra-Termination.ps1` is a well-structured, production-ready script for cloud-only Microsoft 365 user offboarding. It follows PowerShell best practices with proper error handling, logging, and modular design. The script effectively handles the critical security tasks of disabling accounts and revoking sessions while preserving email access through shared mailbox conversion.

**Suitability:** Organizations with pure cloud Microsoft 365 deployments
**Maintenance:** Active development
**Code Quality:** High

---

*End of Review*
