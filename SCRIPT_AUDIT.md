# PowerShell Scripts Repository - Comprehensive Audit Report

**Audit Date:** January 2026
**Author:** dangitbobby10
**Total Scripts:** 25 PowerShell scripts

---

## Table of Contents

1. [Repository Overview](#repository-overview)
2. [General SysAdmin Scripts](#general-sysadmin-scripts)
3. [MS365 & Entra Scripts](#ms365--entra-scripts)
4. [In Development Scripts](#in-development-scripts)
5. [Retired Scripts](#retired-scripts)
6. [Security Considerations](#security-considerations)
7. [Dependencies Summary](#dependencies-summary)

---

## Repository Overview

This repository contains a collection of PowerShell scripts designed for Windows system administration, Microsoft 365 (MS365) management, and Azure/Entra ID administration. The scripts are organized into four main categories:

| Category | Script Count | Status |
|----------|-------------|--------|
| General SysAdmin Scripts | 7 | Active |
| MS365 & Entra Scripts | 4 | Active |
| In Development | 1 | Beta/Testing |
| Retired | 13 | Deprecated |

---

## General SysAdmin Scripts

### 1. Adobe_Acrobat-All_Versions-Uninstall.ps1

**Location:** `General SysAdmin Scripts/`

**Purpose:** Automatically uninstalls all versions of Adobe Acrobat from a Windows system.

**Functionality:**
- Searches three registry paths for installed Adobe Acrobat products:
  - `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
  - `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*`
  - `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
- Identifies applications with "Adobe Acrobat" in the DisplayName
- Modifies MSI uninstall strings from `/I` to `/X` for proper uninstallation
- Executes silent uninstallation (`/qn /norestart`)

**Dependencies:** None (uses native Windows cmdlets)

**Use Case:** Mass deployment/removal of Adobe Acrobat across enterprise environments

---

### 2. Deploy uBlock Origin with PS (Edge & Chrome).ps1

**Location:** `General SysAdmin Scripts/`

**Purpose:** Force-deploys uBlock Origin browser extension to Chrome and Edge via Group Policy registry keys.

**Functionality:**
- Creates registry keys under Policy paths:
  - Chrome: `HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist`
  - Edge: `HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist`
- Adds extension IDs for uBlock Origin:
  - Chrome: `cjpalhdlnbpafiamejdnhcphjbkeiagm`
  - Edge: `odfafepnkmbhccpbejgmiehpchacaeak`

**Dependencies:** None (uses native Windows cmdlets)

**Use Case:** Enterprise ad-blocking deployment without user intervention

---

### 3. Ghetto_Logon_Events.ps1

**Location:** `General SysAdmin Scripts/`

**Purpose:** Monitors and logs Windows logon events without third-party software.

**Functionality:**
- Queries Windows Security Event Log for events in the last hour:
  - Event ID 4624: Successful logon
  - Event ID 4625: Failed logon
  - Event ID 4634: Logout
- Filters out system accounts (DWM-, UMFD-, SYSTEM, localhost$)
- Exports events to CSV with timestamps, usernames, and event types

**Dependencies:** None (designed for Task Scheduler execution)

**Use Case:** Basic logon auditing for compliance or troubleshooting

---

### 4. DHCP - Locate Lease or Reservation via MAC.ps1

**Location:** `General SysAdmin Scripts/Server Admin/`

**Purpose:** Searches DHCP server for leases/reservations matching a MAC address.

**Functionality:**
- Prompts for MAC address input (without delimiters)
- Transforms input to standard format (XX-XX-XX-XX-XX-XX)
- Queries all DHCP scopes on the specified server
- Returns matching lease/reservation information

**Dependencies:**
- DHCP Server PowerShell module
- Administrative access to DHCP server

**Configuration Required:**
- `$DhcpServer` - DHCP server name/IP

---

### 5. Event Viewer 4740 (lockoutEventId) -- All DC Lookup.ps1

**Location:** `General SysAdmin Scripts/Server Admin/`

**Purpose:** Identifies which Domain Controller recorded account lockout events for a specific user.

**Functionality:**
- Prompts for username to search
- Retrieves all Domain Controllers in the domain
- Queries each DC's Security log for Event ID 4740 (Account Lockout)
- Displays lockout time, DC name, and source computer

**Dependencies:**
- Active Directory PowerShell module
- Administrative access to Domain Controllers

**Configuration Required:**
- `$domain` - Domain name (e.g., contoso.local)

---

### 6. IIS (FTP) expCSV - Virtual Dir Physical Path.ps1

**Location:** `General SysAdmin Scripts/Server Admin/`

**Purpose:** Exports IIS virtual directory paths to CSV for documentation.

**Functionality:**
- Retrieves all IIS sites using WebAdministration module
- Extracts virtual directory names and physical paths
- Exports to CSV on user's desktop

**Dependencies:**
- WebAdministration PowerShell module
- IIS installed and configured

---

### 7. Server Service Monitor and Email Alerts.ps1

**Location:** `General SysAdmin Scripts/Server Admin/`

**Purpose:** Monitors Windows services and sends email alerts on failures with auto-restart capability.

**Functionality:**
- Monitors specified services (default: IISADMIN, SMTPSVC)
- Attempts automatic restart if service is stopped
- Sends email notification via SMTP with status report
- Uses Windows Credential Manager for secure credential storage

**Dependencies:**
- CredentialManager PowerShell module
- SMTP server access

**Configuration Required:**
- `$services` - Array of service names to monitor
- `$emailSmtpServer` - SMTP server address
- `$emailSmtpPort` - SMTP port (typically 587)
- `$emailFrom` / `$emailTo` - Email addresses
- Stored credentials via `New-StoredCredential`

---

## MS365 & Entra Scripts

### 8. Calendar-Permissions.ps1

**Location:** `MS365 & Entra Scripts/Calendar Permissions/`

**Purpose:** Interactive tool for managing Exchange Online calendar permissions.

**Functionality:**
- Connects to Exchange Online with interactive authentication
- Supports multiple calendar folder name variations (localization)
- **View Operations:**
  - Display current calendar permissions
  - Show delegate permissions with options (View Private Events, Manage Categories)
  - Display default sharing permissions
- **Modify Operations:**
  - Add/update calendar permissions (10 permission levels: Owner to LimitedDetails)
  - Add/update delegate permissions with additional options
  - Remove calendar/delegate permissions
  - Set default organization sharing permissions
- Handles shared mailbox permissions
- Loop functionality for managing multiple mailboxes in one session

**Permission Levels:**
| Level | Name | Description |
|-------|------|-------------|
| 1 | Owner | Full access to all items and folders |
| 2 | PublishingEditor | Read, create, modify, delete items/subfolders |
| 3 | Editor | Read, create, modify, delete items |
| 4 | PublishingAuthor | Read, create items/subfolders. Modify own only |
| 5 | Author | Create/read items; edit/delete own |
| 6 | NonEditingAuthor | Read and create; delete own only |
| 7 | Reviewer | Read only |
| 8 | Contributor | Create items only |
| 9 | AvailabilityOnly | Free/busy only (DEFAULT) |
| 10 | LimitedDetails | Subject and location only |

**Dependencies:**
- ExchangeOnlineManagement module

---

### 9. MS365Entra-Termination.ps1

**Location:** `MS365 & Entra Scripts/Offboarding/`

**Purpose:** Automates user termination in cloud-only Microsoft Entra ID environments.

**Functionality:**
- **Pre-termination Export:**
  - Group memberships (MS365, Security, Distribution)
  - License assignments with friendly names
- **Termination Actions:**
  - Block sign-in
  - Revoke all active sessions
  - Reset password to random 21-character complex string
  - Rename display name (append "- Email Archive")
  - Hide from Global Address List
  - Convert mailbox to Shared
  - Add mailbox delegates (up to 3)
  - Set Out of Office message
  - Remove from admin roles

**Input:** CSV file (`Term_User.csv`) with columns:
- `Term_User_UPN` - User to terminate
- `Delegate1`, `Delegate2`, `Delegate3` - Mailbox delegates
- `OOO` - Out of Office message

**Dependencies:**
- Microsoft.Graph.Authentication
- Microsoft.Graph.Identity.DirectoryManagement
- Microsoft.Graph.Users
- Microsoft.Graph.Users.Actions
- Microsoft.Graph.Groups
- ExchangeOnlineManagement

**Requires:** PowerShell 7.0+

---

### 10. Mailbox-Distro-Report-SingleUser.ps1

**Location:** `MS365 & Entra Scripts/Reporting/`

**Purpose:** Generates detailed mailbox report for a single user.

**Report Includes:**
- Account status (ACTIVE/BLOCKED)
- Mailbox type (User/Shared)
- Display name, primary email, UPN
- All email aliases
- Delegate permissions:
  - Full Access
  - SendAs
  - SendOnBehalf
- Mailbox size (GB)
- Litigation Hold status
- Archive mailbox status
- License assignment status

**Dependencies:**
- Microsoft.Graph.Authentication
- Microsoft.Graph.Users
- Microsoft.Graph.Groups
- ExchangeOnlineManagement

**Requires:** PowerShell 7.0+

---

### 11. Mailbox-Distro-Report.ps1

**Location:** `MS365 & Entra Scripts/Reporting/`

**Purpose:** Comprehensive organization-wide mailbox and distribution group report.

**Report Coverage:**
- All user mailboxes (excludes guest accounts)
- All shared mailboxes
- All distribution groups
- All mail-enabled security groups

**Report Fields:**
| Field | Description |
|-------|-------------|
| AccountStatus | ACTIVE or BLOCKED |
| Type | Mailbox, Shared Mailbox, Distribution Group, Mail-Enabled Security Group |
| DisplayName | Display name |
| PrimaryEmail | Primary SMTP address |
| UserPrincipalName | UPN |
| Aliases | Semicolon-separated list |
| Delegates | Full Access permissions |
| SendAs | SendAs permissions |
| SendOnBehalf | SendOnBehalf permissions |
| MailboxSizeGB | Size in GB |
| LitigationHold | True/False |
| ArchiveEnabled | True/False |
| LicenseAssigned | True/False |

**Features:**
- Automatic session reconnection
- Progress tracking with ETA
- Error logging to separate CSV
- Rate limit handling

**Dependencies:**
- Microsoft.Graph.Authentication
- Microsoft.Graph.Users
- Microsoft.Graph.Groups
- ExchangeOnlineManagement

**Requires:** PowerShell 7.0+

---

## In Development Scripts

### 12. [testing] Migrate OneDrive Files To SharePoint.ps1

**Location:** `~In Development/Migrate User's OneDrive to SharePoint/`

**Purpose:** Copies/moves terminated user's OneDrive files to SharePoint site.

**Status:** Beta/Prototype

**Functionality:**
- Authenticates using certificate-based app registration
- Prompts for user email and validates existence
- Creates folder structure in destination SharePoint library
- Copies files maintaining directory structure
- Option to change from Copy-PnPFile to Move-PnPFile

**Configuration Required:**
- `$clientid` - Azure App Registration Client ID
- `$cert_pfx_path` - Path to PFX certificate
- `$cert_pfx_pw` - Certificate password
- `$tenant_domain` - Tenant domain (e.g., contoso.com)
- `$sharePointSiteUrl` - Destination site URL
- `$libraryPath` - Document library name
- `$TEMP_folderpath` - Parent folder for offboarded user data

**Dependencies:**
- PnP.PowerShell module
- PowerShell 7+
- Azure App Registration with certificate auth
- MS Graph API permissions configured

**Security Note:** Certificate password is stored in plain text - should use secure credential storage in production.

---

## Retired Scripts

### Hybrid Environment Offboarding Scripts

**Locations:**
- `~Retired/HYBRID Environments/All OUs/`
- `~Retired/HYBRID Environments/Select OUs/`
- `~Retired/Offboarding/HYBRID Environments/All OUs/`
- `~Retired/Offboarding/HYBRID Environments/Select OUs/`

**Scripts:**
- `HYBRID All OUs -- Offboarding.ps1`
- `HYBRID Select OUs -- Offboarding.ps1`
- `LicenseFriendlyNamesScript.ps1`

**Purpose:** Employee offboarding for hybrid AD/Azure environments.

**Functionality:**
- GUI form for entering offboarding details
- **Active Directory Actions:**
  - Disable AD account
  - Reset password to complex random string
  - Clear IP Phone attribute
  - Remove group memberships
  - Hide from GAL (msExchHideFromAddressLists)
  - Move to Disabled Users OU
  - Update description with termination date
  - Update display name prefix
  - Transfer home directory to offboard location
- **Azure AD/MS365 Actions:**
  - Trigger AAD Connect delta sync
  - Block MS365 sign-in
  - Revoke all sessions
  - Remove admin roles
  - Convert to shared mailbox
  - Smart license removal based on mailbox size and archive status
  - Configure email forwarding
  - Add delegates and SendAs permissions
  - Set Out of Office message
  - Remove from all MS365/Security/Distribution groups
- **Export:** User configuration to CSV before changes

**License Removal Logic:**
| Condition | Action |
|-----------|--------|
| ≥50GB + Archive Enabled | Keep E3/E5 only |
| ≥50GB + No Archive | Keep E3/E5 only |
| <50GB + Archive Enabled | Keep E3/E5/Exchange Archiving |
| <50GB + No Archive | Remove all licenses |

**Dependencies:**
- MSOnline module
- ExchangeOnlineManagement module
- AzureAD module
- ActiveDirectory module

---

### Cloud-Only Offboarding Script

**Location:** `~Retired/Offboarding/CLOUD Environments/`

**Scripts:**
- `CLOUD -- Offboarding.ps1`
- `LicenseFriendlyNamesScript.ps1`

**Purpose:** Employee offboarding for cloud-only (no on-premises AD) environments.

**Functionality:** Similar to hybrid scripts but without AD-specific actions. Uses email address instead of AD username for user identification.

---

### Logon Reporting Scripts

**Location:** `~Retired/Logon Reporting/`

#### AD_LastLogon_Report.ps1
**Purpose:** Reports last logon times from all Domain Controllers.

**Features:**
- Queries all DCs for accurate lastLogon attribute
- Includes msDS-LastSuccessfulInteractiveLogonTime
- Reports password expiration dates
- Exports comprehensive user details to CSV

#### AzureActiveDirectory_LastLogon_Report.ps1
**Purpose:** Reports Azure AD sign-in activity for the last 30 days.

**Features:**
- Fetches from Azure AD Audit Sign-In Logs
- Includes IP address, location, client app, device info
- Tracks both interactive and non-interactive sign-ins
- Measures script execution time

#### Office365_LastLogon(LastAction)_Report.ps1
**Purpose:** Comprehensive MS365 audit report with license reduction recommendations.

**Report Includes:**
- Last user action time and last logon time
- Mailbox size and type (User/Shared)
- MFA status (RSA MFA / Microsoft MFA)
- Full delegate, SendAs, SendOnBehalf permissions
- In-Place Archive status and size
- Litigation Hold status
- License assignment with friendly names
- **License Reduction Check:** Automated recommendation based on:
  - Mailbox size (<50GB threshold)
  - Archive status
  - Litigation Hold status
  - Sign-in status (Enabled/Blocked)

---

### LicenseFriendlyNamesScript.ps1 (Supporting Script)

**Purpose:** Maps MS365 license SKUs to human-readable names.

**License Mappings Include:**
| SKU | Friendly Name |
|-----|---------------|
| AAD_PREMIUM | Azure Active Directory Premium P1 |
| AAD_PREMIUM_P2 | Azure Active Directory Premium P2 |
| ENTERPRISEPACK | Office 365 E3 |
| ENTERPRISEPREMIUM | Office 365 E5 |
| STANDARDPACK | Office 365 E1 |
| EXCHANGEARCHIVE_ADDON | Exchange Online Archiving |
| POWER_BI_PRO | Power BI Pro |
| PROJECTPROFESSIONAL | Project Plan 3 |
| VISIOCLIENT | Visio Plan 2 |
| And more... | |

---

## Security Considerations

### Credential Handling

| Script | Method | Risk Level | Recommendation |
|--------|--------|------------|----------------|
| OneDrive Migration | Plain text PFX password | High | Use Key Vault or secure credential |
| Service Monitor | Windows Credential Manager | Low | Acceptable |
| Offboarding Scripts | Interactive login | Low | Acceptable |
| Reporting Scripts | Interactive login | Low | Acceptable |

### Permissions Required

| Script Category | Required Permissions |
|-----------------|---------------------|
| AD Scripts | Domain Admin or delegated AD permissions |
| MS365/Entra Scripts | Global Admin or specific admin roles |
| DHCP Script | DHCP Server admin |
| IIS Script | Local admin on IIS server |

### Audit Trail

Most scripts include:
- Colored console output for status tracking
- CSV export of changes for compliance
- Error logging to separate log files

### Sensitive Operations

The following operations should be reviewed before execution:
- Password resets
- Account disabling
- License removal
- Group membership changes
- Home directory transfers

---

## Dependencies Summary

### PowerShell Modules Required

| Module | Scripts Using |
|--------|---------------|
| ExchangeOnlineManagement | Calendar Permissions, Termination, Reporting |
| Microsoft.Graph.* | Termination, Reporting (MS365/Entra) |
| AzureAD | Retired offboarding scripts |
| MSOnline | Retired offboarding scripts |
| ActiveDirectory | Hybrid offboarding, AD Last Logon |
| PnP.PowerShell | OneDrive Migration |
| WebAdministration | IIS Export |
| CredentialManager | Service Monitor |

### PowerShell Version Requirements

| Requirement | Scripts |
|-------------|---------|
| PowerShell 7.0+ | MS365Entra-Termination, Mailbox Reports, OneDrive Migration |
| Windows PowerShell 5.1 | All other scripts |

### Azure/MS365 Requirements

- Azure AD App Registration (for certificate-based auth)
- Microsoft Graph API permissions
- Exchange Online permissions
- SharePoint Online permissions (for OneDrive migration)

---

## Quick Reference

### Active Scripts by Use Case

| Use Case | Script |
|----------|--------|
| Uninstall Adobe Acrobat | `Adobe_Acrobat-All_Versions-Uninstall.ps1` |
| Deploy ad blocker | `Deploy uBlock Origin with PS (Edge & Chrome).ps1` |
| Monitor logon events | `Ghetto_Logon_Events.ps1` |
| Find DHCP lease by MAC | `DHCP - Locate Lease or Reservation via MAC.ps1` |
| Find account lockout source | `Event Viewer 4740 (lockoutEventId) -- All DC Lookup.ps1` |
| Export IIS virtual directories | `IIS (FTP) expCSV - Virtual Dir Physical Path.ps1` |
| Monitor Windows services | `Server Service Monitor and Email Alerts.ps1` |
| Manage calendar permissions | `Calendar-Permissions.ps1` |
| Terminate cloud user | `MS365Entra-Termination.ps1` |
| Single user mailbox report | `Mailbox-Distro-Report-SingleUser.ps1` |
| Organization mailbox report | `Mailbox-Distro-Report.ps1` |

---

*End of Audit Report*
