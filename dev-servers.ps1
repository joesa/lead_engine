#!/usr/bin/env pwsh
#
# Start / stop / restart the local dev servers for this workspace.
#
#   .\dev-servers.ps1 start      # free the ports, then start everything
#   .\dev-servers.ps1 stop       # stop everything and free the ports
#   .\dev-servers.ps1 restart    # stop + start
#   .\dev-servers.ps1 status     # what is running / listening
#
# A single server can be targeted by name, e.g.
#   .\dev-servers.ps1 restart dashboard
#

param(
    [Parameter(Mandatory=$false, Position=0)]
    [ValidateSet("start", "stop", "restart", "status")]
    [string]$Action = "start",

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Target = ""
)

# Get script root directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunDir = Join-Path $ScriptRoot ".dev-servers"
$LogDir = Join-Path $RunDir "logs"

# Full paths for node and npm
$NodePath = "C:\Program Files\nodejs\node.exe"
$NpmPath = "C:\Program Files\nodejs\npm.cmd"

# name|directory|port|command
# Note: Vite uses --port, Next.js uses -p
$servers = @(
    @{Name="renderer"; Dir="custom-closets-websites"; Port=3000; Cmd="npm run dev"; IsVite=$false},
    @{Name="dashboard"; Dir="closet-dashboard"; Port=3001; Cmd="npm run dev"; IsVite=$false},
    @{Name="widget"; Dir="closet-widget"; Port=5173; Cmd="npm run dev"; IsVite=$true}
)

$ReadyTimeout = 90

function Get-SelectedServers {
    param([string]$Want = "")

    foreach ($entry in $servers) {
        if ([string]::IsNullOrEmpty($Want) -or $entry.Name -eq $Want) {
            $entry
        }
    }

    if ([string]::IsNullOrEmpty($Want) -eq $false) {
        $known = ($servers | ForEach-Object { $_.Name }) -join ", "
        Write-Host ("Unknown server '{0}'. Known: {1}" -f $Want, $known) -ForegroundColor Red
        exit 1
    }
}

function Get-ProcessOnPort {
    param([int]$Port)

    $processIds = @()

    # Try netstat first (most reliable on Windows)
    $netstatOutput = netstat -ano | Select-String "TCP.*:$Port\s+.*LISTENING" 2>$null
    if ($netstatOutput) {
        foreach ($line in $netstatOutput) {
            if ($line -match "\s+(\d+)\s*$") {
                $id = $matches[1]
                if ($id -and $id -ne 0) {
                    $processIds += $id
                }
            }
        }
    }

    return $processIds | Sort-Object -Unique
}

function Free-Port {
    param([int]$Port, [string]$Label)

    $processIds = Get-ProcessOnPort -Port $Port
    if ($processIds.Count -eq 0) { return $true }

    $labelText = ""
    if ($Label) {
        $labelText = " ($Label)"
    }
    Write-Host ("  Port {0} busy{1}: killing process(es) {2}" -f $Port, $labelText, ($processIds -join ", ")) -ForegroundColor Yellow

    foreach ($id in $processIds) {
        try {
            $process = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($process) {
                $processName = $process.ProcessName
                Write-Host ("    Killing PID {0} ({1})" -f $id, $processName) -ForegroundColor Yellow
                Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
                # Also try to kill any child processes
                $children = Get-WmiObject Win32_Process | Where-Object {$_.ParentProcessId -eq $id}
                foreach ($child in $children) {
                    Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Host ("    Could not kill PID {0}: {1}" -f $id, $errorMsg) -ForegroundColor Yellow
        }
    }

    # Wait for port to be released (with retries)
    for ($i = 0; $i -lt 40; $i++) {
        $processIds = Get-ProcessOnPort -Port $Port
        if ($processIds.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    }

    # Additional delay to ensure handles are released
    Start-Sleep -Milliseconds 1000

    if ((Get-ProcessOnPort -Port $Port).Count -gt 0) {
        Write-Host "  ERROR: Port $Port is still in use" -ForegroundColor Red
        return $false
    }

    return $true
}

function Stop-One {
    param($Entry)

    $name = $Entry.Name
    $port = $Entry.Port
    $pidFile = Join-Path $RunDir "$name.pid"

    if (Test-Path $pidFile) {
        $processId = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($processId -and $processId -match "^\d+$") {
            try {
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host ("  Stopping {0} (PID {1})" -f $name, $processId) -ForegroundColor Cyan
                    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                    for ($i = 0; $i -lt 20; $i++) {
                        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                        if (-not $process) { break }
                        Start-Sleep -Milliseconds 250
                    }
                }
            } catch {}
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    Free-Port -Port $port -Label $name | Out-Null
}

function Start-One {
    param($Entry)

    $name = $Entry.Name
    $dir = $Entry.Dir
    $port = $Entry.Port
    $cmd = $Entry.Cmd
    $pidFile = Join-Path $RunDir "$name.pid"
    $logFile = Join-Path $LogDir "$name.log"

    $fullDir = Join-Path $ScriptRoot $dir
    if (-not (Test-Path $fullDir)) {
        Write-Host ("  SKIP {0}: {1} not found" -f $name, $dir) -ForegroundColor Yellow
        return $false
    }

    if (-not (Free-Port -Port $port -Label $name)) {
        return $false
    }

    # Create log file header
    "" | Out-File -FilePath $logFile -Encoding utf8

    # Build npm command with PATH set and redirect both stdout and stderr to log file
    $npmCmd = "set PATH=C:\Program Files\nodejs;%PATH% && `"$NpmPath`" run dev"
    if ($Entry.IsVite) {
        $npmCmd += " -- --port $port"
    } else {
        $npmCmd += " -- -p $port"
    }
    $npmCmd += " >> `"$logFile`" 2>&1"

    # Start the process
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $npmCmd" -WorkingDirectory $fullDir -NoNewWindow -PassThru | Out-Null

    # Get the PID of the newly created process
    Start-Sleep -Milliseconds 1000
    $processId = (Get-Process node -ErrorAction SilentlyContinue | Where-Object {$_.StartTime -gt (Get-Date).AddSeconds(-5)} | Sort-Object StartTime -Descending | Select-Object -First 1).Id

    if (-not $processId) {
        # Fallback: use the PID of the first node process we find
        $processId = (Get-Process node -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1).Id
    }

    if (-not $processId) {
        Write-Host ("  ERROR: Could not find node process for {0}" -f $name) -ForegroundColor Red
        return $false
    }

    # Write PID to file
    $processId | Out-File -FilePath $pidFile -Encoding ascii

    Write-Host ("  Starting {0} on port {1} (PID {2}, log {3})" -f $name, $port, $processId, $logFile) -ForegroundColor Cyan

    # Wait for server to start (give Next.js/Vite time to initialize)
    Start-Sleep -Seconds 8

    # Check if HTTP server is responding with a successful status code (2xx-3xx)
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $response = Invoke-WebRequest -Uri ("http://localhost:{0}/" -f $port) -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response -and $response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                Write-Host ("  Ready:    {0} -> http://localhost:{1}" -f $name, $port) -ForegroundColor Green
                return $true
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }

    Write-Host ("  WARNING: {0} may have started (check {1})" -f $name, $logFile) -ForegroundColor Yellow
    return $true
}

function Show-Status {
    Write-Host ""
    Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f "NAME", "PORT", "STATE", "DETAIL") -ForegroundColor Cyan
    Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f "----", "----", "-----", "------") -ForegroundColor DarkCyan

    foreach ($entry in $servers) {
        $name = $entry.Name
        $port = $entry.Port
        $pidFile = Join-Path $RunDir "$name.pid"
        $processId = $null
        $httpStatus = $null

        if (Test-Path $pidFile) {
            $processId = Get-Content $pidFile -ErrorAction SilentlyContinue
        }

        # Check if port is responding to HTTP requests (more reliable than PID check)
        $portResponding = $false
        $httpError = $false
        try {
            $response = Invoke-WebRequest -Uri ("http://localhost:{0}/" -f $port) -TimeoutSec 1 -UseBasicParsing -ErrorAction Stop
            $httpStatus = $response.StatusCode
            if ($response -and $response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                $portResponding = $true
            } else {
                $httpError = $true
            }
        } catch {
            $httpStatus = $_.Exception.Response.StatusCode.Value__
        }

        if ($portResponding) {
            Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f $name, $port, "running", "http://localhost:$port") -ForegroundColor Green
        } elseif ($httpError -and $processId -and $processId -match "^\d+$") {
            # Server responding but with error status (500, etc.)
            try {
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f $name, $port, "degraded", "PID $processId | HTTP $httpStatus | http://localhost:$port") -ForegroundColor Yellow
                    continue
                }
            } catch {}
            Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f $name, $port, "degraded", "HTTP $httpStatus | http://localhost:$port") -ForegroundColor Yellow
        } elseif ($processId -and $processId -match "^\d+$") {
            try {
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f $name, $port, "running", "PID $processId | http://localhost:$port") -ForegroundColor Green
                    continue
                }
            } catch {}
            Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f $name, $port, "foreign", ("port held by PID(s): {0}" -f ($processId -join ", "))) -ForegroundColor Yellow
        } else {
            Write-Host ("{0,-12} {1,-6} {2,-12} {3}" -f $name, $port, "stopped", "-") -ForegroundColor Gray
        }
    }
}

# Create required directories
New-Item -Path $RunDir -ItemType Directory -Force | Out-Null
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

# Get selected servers
$chosen = Get-SelectedServers -Want $Target

$targetLabel = ""
if ($Target) {
    $targetLabel = " ($Target)"
}

switch ($Action) {
    "start" {
        Write-Host ("Starting dev servers{0}..." -f $targetLabel) -ForegroundColor Cyan
        $failed = $false
        foreach ($entry in $chosen) {
            if (-not (Start-One -Entry $entry)) { $failed = $true }
        }
        Write-Host ""
        Show-Status
        exit ([int]$failed)
    }

    "stop" {
        Write-Host ("Stopping dev servers{0}..." -f $targetLabel) -ForegroundColor Cyan
        foreach ($entry in $chosen) {
            Stop-One -Entry $entry
        }
        Write-Host ""
        Show-Status
    }

    "restart" {
        Write-Host ("Restarting dev servers{0}..." -f $targetLabel) -ForegroundColor Cyan
        foreach ($entry in $chosen) {
            Stop-One -Entry $entry
        }
        $failed = $false
        foreach ($entry in $chosen) {
            if (-not (Start-One -Entry $entry)) { $failed = $true }
        }
        Write-Host ""
        Show-Status
        exit ([int]$failed)
    }

    "status" {
        Show-Status
    }
}
