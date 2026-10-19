#Requires -Version 7.0

param(
    [Parameter(Position = 0)]
    [string]$BaseUrl = "http://localhost:8080",
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host "Usage: .\import-test-safes.ps1 [base-url]"
    Write-Host "Upload backend/testdata/*.psafe3 with overwrite=true."
    Write-Host "The default base URL is http://localhost:8080."
    return
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$testdata = Join-Path $PSScriptRoot "backend/testdata"
$safes = @(Get-ChildItem -LiteralPath $testdata -Filter "*.psafe3" -File | Sort-Object Name)
if ($safes.Count -eq 0) {
    throw "No test safes found in $testdata."
}

$page = Invoke-WebRequest -Uri "$BaseUrl/web/" -SessionVariable session
$csrfMatch = [regex]::Match($page.Content, 'window.__PWSAFE_CSRF_TOKEN="([^"]*)"')
if (-not $csrfMatch.Success -or $csrfMatch.Groups[1].Value.Length -eq 0) {
    throw "No CSRF token found at $BaseUrl/web/."
}
$headers = @{ "X-PWSAFE-CSRF-Token" = $csrfMatch.Groups[1].Value }

$status = Invoke-RestMethod -Uri "$BaseUrl/api/auth/status" -WebSession $session
switch ($status.mode) {
    "enabled" {
        $password = Read-Host "Service password" -AsSecureString
        $credential = [System.Management.Automation.PSCredential]::new("service", $password)
        $loginBody = $null
        try {
            $loginBody = @{ password = $credential.GetNetworkCredential().Password } | ConvertTo-Json -Compress
            $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/auth/login" `
                -WebSession $session -Headers $headers `
                -ContentType "application/json; charset=utf-8" -Body $loginBody
            $response | ConvertTo-Json -Compress
        } finally {
            $loginBody = $null
            $credential = $null
            $password.Dispose()
        }
    }
    "disabled" {}
    default {
        throw "Service authentication is not configured. Complete setup in the web UI first."
    }
}

foreach ($safe in $safes) {
    Write-Host "Import: $($safe.Name)"
    $response = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/api/providers/static/files?overwrite=true" `
        -WebSession $session -Headers $headers -Form @{ file = $safe }
    $response | ConvertTo-Json -Compress
}

Write-Host "Imported $($safes.Count) test safes."
