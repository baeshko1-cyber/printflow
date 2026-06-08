# YouTube Music Downloader
# Skachat vse treki iz tracks.txt s YouTube

$tracksFile = "$HOME\Desktop\tracks.txt"
$output     = "$HOME\Desktop\Muzyka"
$ytdlp      = "$HOME\Desktop\yt-dlp.exe"

if (-not (Test-Path $tracksFile)) {
    Write-Host "Ne najden fayl: $tracksFile"
    Read-Host "Enter"
    exit
}

New-Item -ItemType Directory -Path $output -Force | Out-Null

$tracks = Get-Content $tracksFile | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }
$total  = $tracks.Count
$i = 0; $ok = 0; $fail = 0

Write-Host "Vsego trekov: $total"
Write-Host "Sohranyayu v: $output"
Write-Host ""

foreach ($track in $tracks) {
    $i++
    $safe  = $track -replace '[\\/:*?"<>|]', '_'
    $dest  = Join-Path $output "$safe.mp3"

    if (Test-Path $dest) {
        Write-Host "[$i/$total] SKIP: $track"
        $ok++
        continue
    }

    Write-Host "[$i/$total] $track" -NoNewline

    $result = & $ytdlp "ytsearch1:$track" `
        -x --audio-format mp3 `
        --no-playlist `
        -o "$output\$safe.%(ext)s" `
        --quiet --no-warnings 2>&1

    if (Test-Path $dest) {
        Write-Host " OK"
        $ok++
    } else {
        Write-Host " FAIL"
        $fail++
    }

    Start-Sleep -Milliseconds 800
}

Write-Host ""
Write-Host "================================"
Write-Host "Gotovo! OK: $ok | Fail: $fail"
Write-Host "Fayly: $output"
Write-Host "================================"
Read-Host "Enter"
