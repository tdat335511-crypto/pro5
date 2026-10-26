# =======================================================
# Billiards Media - Local Project Asset Sync Server (Port 5555)
# Tự động nhận ảnh và JSON từ admin.html để ghi trực tiếp vào ổ đĩa
# =======================================================

$port = 5555
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $projectRoot) { $projectRoot = Get-Location }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")

try {
    $listener.Start()
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " [OK] Billiards Media Sync Server running on http://127.0.0.1:$port/" -ForegroundColor Green
    Write-Host " Project root: $projectRoot" -ForegroundColor Cyan
    Write-Host " Ready to receive auto-sync requests from admin.html..." -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Green
} catch {
    Write-Host "Error starting HTTP listener: $_" -ForegroundColor Red
    exit 1
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # CORS Headers
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $rawUrl = $request.RawUrl

        # Health check endpoint
        if ($rawUrl -eq "/api/status") {
            $json = @{
                status = "online"
                port = $port
                root = $projectRoot
                timestamp = (Get-Date).ToString("o")
            } | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            continue
        }

        # Save Image Endpoint
        if ($rawUrl -eq "/api/save-image" -and $request.HttpMethod -eq "POST") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $payload = $body | ConvertFrom-Json

                $relPath = $payload.path
                $cleanRelPath = $relPath.TrimStart('/', '\').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                $base64Data = $payload.base64

                if ($base64Data -match "^data:image/[^;]+;base64,(.+)$") {
                    $base64Data = $matches[1]
                }

                $bytes = [System.Convert]::FromBase64String($base64Data)
                $targetFile = [System.IO.Path]::Combine($projectRoot, $cleanRelPath)
                $parentDir = [System.IO.Path]::GetDirectoryName($targetFile)

                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }

                [System.IO.File]::WriteAllBytes($targetFile, $bytes)
                Write-Host "[Auto-Sync] Saved image: $cleanRelPath ($($bytes.Length) bytes)" -ForegroundColor Green

                $result = @{
                    success = $true
                    path = $cleanRelPath
                    bytes = $bytes.Length
                    savedAt = (Get-Date).ToString("o")
                } | ConvertTo-Json

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } catch {
                Write-Host "[Auto-Sync ERROR] Failed to save image: $_" -ForegroundColor Red
                $response.StatusCode = 500
                $errJson = @{ success = $false; error = "$_" } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            $response.Close()
            continue
        }

        # Save JSON Endpoint
        if ($rawUrl -eq "/api/save-json" -and $request.HttpMethod -eq "POST") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $payload = $body | ConvertFrom-Json

                $relPath = $payload.path
                $cleanRelPath = $relPath.TrimStart('/', '\').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                
                $rawContent = $payload.content
                if ($rawContent -is [string]) {
                    $content = $rawContent
                } elseif ($rawContent.value -and ($rawContent.value -is [string])) {
                    $content = $rawContent.value
                } else {
                    $content = $rawContent | ConvertTo-Json -Depth 20
                }

                $targetFile = [string][System.IO.Path]::Combine($projectRoot, $cleanRelPath)
                $parentDir = [System.IO.Path]::GetDirectoryName($targetFile)

                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }

                [System.IO.File]::WriteAllText([string]$targetFile, [string]$content, [System.Text.Encoding]::UTF8)
                Write-Host "[Auto-Sync] Saved data: $cleanRelPath ($($content.Length) chars)" -ForegroundColor Cyan

                $result = @{
                    success = $true
                    path = $cleanRelPath
                    savedAt = (Get-Date).ToString("o")
                } | ConvertTo-Json

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } catch {
                Write-Host "[Auto-Sync ERROR] Failed to save data: $_" -ForegroundColor Red
                $response.StatusCode = 500
                $errJson = @{ success = $false; error = "$_" } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            $response.Close()
            continue
        }

        # Unknown Endpoint
        $response.StatusCode = 404
        $buffer = [System.Text.Encoding]::UTF8.GetBytes('{"error": "Endpoint not found"}')
        $response.ContentType = "application/json"
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    } catch {
        Write-Host "Error processing request: $_" -ForegroundColor Red
    }
}
