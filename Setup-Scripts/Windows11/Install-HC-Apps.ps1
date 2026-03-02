# Chocolatey Windows Setup Script
# Run as Administrator

# Set execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# Install Chocolatey if not present
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# Refresh environment
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Install Chrome (do NOT make default or sign in)
# Use --no-default-browser to prevent setting as default
# Use --skip-hooks to avoid post-install sign-in prompts
choco install googlechrome -y --no-progress --params="'/DoNotRegisterForSSO'"
# Note: Chrome will still prompt for sign-in on first run, user must decline

# Install Adobe Acrobat Reader DC and set as default for PDF
choco install adobereader -y --no-progress
# Set Adobe as default handler for PDF files
$pdfProgID = "AcroExch.Document.DC"
$pdfExt = ".pdf"
$pdfPath = "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
if (Test-Path $pdfPath) {
    Set-ItemProperty -Path "HKCR:\$pdfExt\OpenWithProgids" -Name $pdfProgID -Value ([byte[]]@())
    New-Item -Path "HKCR:\$pdfProgID" -Force | Out-Null
    Set-ItemProperty -Path "HKCR:\$pdfProgID" -Name "(Default)" -Value "Adobe Acrobat Document"
    New-Item -Path "HKCR:\$pdfProgID\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "HKRC:\$pdfProgID\shell\open\command" -Name "(Default)" -Value "`"$pdfPath`" `"%1`""
}

# Install Zoom
choco install zoom -y --no-progress

# Install Slack
choco install slack -y --no-progress

# Install Microsoft Office Suite
# Office 2021 Professional Plus (retail)
choco install microsoft-office-2021-professional-plus -y --no-progress
# Or use this for Microsoft 365 (requires license):
# choco install microsoft-office365 -y --no-progress

# Refresh environment variables again
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "Installation complete! Please restart your computer."
Write-Host "Note: On first run of Chrome, decline the sign-in prompt."
Write-Host "Note: Manually set Adobe as default for PDFs in Windows Settings > Apps > Default Apps if needed."
