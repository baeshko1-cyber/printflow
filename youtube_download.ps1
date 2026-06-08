# YouTube Music Downloader
# Skachat vse treki iz tracks.txt s YouTube

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$tracksFile = "$HOME\Desktop\tracks.txt"
$output     = "$HOME\Desktop\Muzyka"
$ytdlp      = "$HOME\Desktop\yt-dlp.exe"

if (-not (Test-Path $tracksFile)) {
    Write-Host "Ne najden fayl: $tracksFile"
    Read-Host "Enter"
    exit
}

if (-not (Test-Path $ytdlp)) {
    Write-Host "Ne najden yt-dlp.exe: $ytdlp"
    Read-Host "Enter"
    exit
}

# Kill any hung yt-dlp processes that may lock the file
Get-Process yt-dlp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Auto-update yt-dlp (download to temp, then replace)
Write-Host "Obnovlyayu yt-dlp..."
$tmp = "$HOME\Desktop\yt-dlp-new.exe"
try {
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $tmp -ErrorAction Stop
    Move-Item -Path $tmp -Destination $ytdlp -Force -ErrorAction Stop
    Write-Host "yt-dlp obnovlen."
} catch {
    Write-Host "Ne udalos obnovit yt-dlp (ispolzuyu tekushchiy): $_"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}
Write-Host ""

New-Item -ItemType Directory -Path $output -Force | Out-Null

$tracks = Get-Content $tracksFile -Encoding UTF8 | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }
$total  = $tracks.Count
$i = 0; $ok = 0; $fail = 0

Write-Host "Vsego trekov: $total"
Write-Host "Sohranyayu v: $output"
Write-Host ""

foreach ($track in $tracks) {
    $i++
    $num = ([string]$i).PadLeft(3, '0')

    $existing = Get-ChildItem -Path $output -Filter "$num *" -File 2>$null
    if ($existing) {
        Write-Host "[$i/$total] SKIP"
        $ok++
        continue
    }

    Write-Host "[$i/$total] $i..." -NoNewline

    $outTemplate = "$output\$num %(title)s.%(ext)s"

    $result = & $ytdlp "ytsearch1:$track" `
        --no-playlist `
        --cookies-from-browser opera `
        -o $outTemplate `
        --no-warnings 2>&1

    $downloaded = Get-ChildItem -Path $output -Filter "$num *" -File 2>$null
    if ($downloaded) {
        Write-Host " OK"
        $ok++
    } else {
        Write-Host " FAIL"
        $errLine = $result | Where-Object { $_ -match "ERROR" } | Select-Object -First 1
        if ($errLine) { Write-Host "  -> $errLine" }
        $fail++
    }

    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "================================"
Write-Host "Gotovo! OK: $ok | Fail: $fail"
Write-Host "Fayly: $output"
Write-Host "================================"
Read-Host "Enter"
