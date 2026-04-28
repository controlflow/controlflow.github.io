param(
    [int]$Port = 4000,
    [switch]$NoBrowser,
    [switch]$SkipBundleInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

function Get-BundlePath {
    $bundle = Get-Command bundle -ErrorAction SilentlyContinue
    if ($bundle) {
        return $bundle.Source
    }

    $fallback = Get-ChildItem "C:\" -Directory -Filter "Ruby*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "bin\\bundle.bat" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

    if ($fallback) {
        return $fallback
    }

    throw "Bundler was not found. Install Ruby with DevKit first."
}

function Invoke-Bundle {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $bundlePath = Get-BundlePath
    $bundleDir = Split-Path -Parent $bundlePath
    $pathEntries = $env:PATH -split ";"
    if ($pathEntries -notcontains $bundleDir) {
        $env:PATH = "$bundleDir;$env:PATH"
    }

    & $bundlePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Bundler command failed: bundle $($Arguments -join ' ')"
    }
}

function Start-BrowserWhenReady {
    param(
        [Parameter(Mandatory = $true)]
        [int]$TargetPort
    )

    Start-Job -ScriptBlock {
        param($PortNumber)

        $url = "http://127.0.0.1:$PortNumber"
        for ($i = 0; $i -lt 120; $i++) {
            try {
                $client = [System.Net.Sockets.TcpClient]::new()
                $async = $client.BeginConnect("127.0.0.1", $PortNumber, $null, $null)
                if ($async.AsyncWaitHandle.WaitOne(500)) {
                    $client.EndConnect($async)
                    $client.Dispose()
                    Start-Process $url
                    return
                }
                $client.Dispose()
            } catch {
                if ($null -ne $client) {
                    $client.Dispose()
                }
            }

            Start-Sleep -Milliseconds 500
        }
    } -ArgumentList $TargetPort | Out-Null
}

if (-not $SkipBundleInstall) {
    Invoke-Bundle -Arguments @("install")
}

if (-not $NoBrowser) {
    Start-BrowserWhenReady -TargetPort $Port
}

Write-Host "Starting Jekyll on http://127.0.0.1:$Port"
Invoke-Bundle -Arguments @("exec", "jekyll", "serve", "--host", "127.0.0.1", "--port", $Port.ToString())
