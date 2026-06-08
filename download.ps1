# Yandex Music Downloader
# Pravaya knopka na fayle -> "Vypolnit s pomoshchyu PowerShell"

$ErrorActionPreference = "SilentlyContinue"
$PLAYLIST = "lk.799fa788-940c-4b6c-9d1c-7316144b09f7"
$OUTPUT   = "$HOME\Desktop\Muzyka"

function Clean-Name($s) {
    $s = $s.Replace('\','_').Replace('/','_').Replace(':','_')
    $s = $s.Replace('*','_').Replace('?','_').Replace('"','_')
    $s = $s.Replace('<','_').Replace('>','_').Replace('|','_')
    if ($s.Length -gt 180) { $s = $s.Substring(0, 180) }
    return $s.Trim()
}

function Get-Token {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================"
    Write-Host "     Shag 1 iz 2 -- Poluchaem token"
    Write-Host "  ================================================"
    Write-Host ""
    Write-Host "  Seychas otkroetsya brauzer."
    Write-Host ""
    Write-Host "  Chto nuzhno sdelat:"
    Write-Host "   1. V brauzere nazhmite [ Razreshit ] ili [ Voyti ]"
    Write-Host "   2. Stranitsya obnovitsya -- SRAZU nazhmite Ctrl+A"
    Write-Host "      v adresnoy stroke, potom Ctrl+C"
    Write-Host "   3. Vernites syuda i nazhmite Ctrl+V"
    Write-Host ""
    Read-Host "  Nazhmite Enter chtoby otkryt brauzer"

    Start-Process "https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d"

    Write-Host ""
    $raw = Read-Host "  Vstavte adres iz brauzera i nazhmite Enter"

    if ($raw -match "access_token=([A-Za-z0-9_-]+)") {
        return $matches[1]
    }
    if ($raw.Length -gt 30) {
        return $raw.Trim()
    }
    Write-Host "  Ne udalos nayti token. Poprobujte eshche raz."
    Read-Host "  Enter dlya vyhoda"
    exit
}

function Get-Headers($token) {
    return @{
        "Authorization"         = "OAuth $token"
        "X-Yandex-Music-Client" = "YandexMusicAndroid/23020251"
        "Accept"                = "application/json"
    }
}

function Call-Api($path, $h) {
    $r = Invoke-RestMethod -Uri ("https://api.music.yandex.net" + $path) -Headers $h -Method Get -ErrorAction Stop
    return $r.result
}

function Get-DirectUrl($infoUrl, $h) {
    try {
        $j   = Invoke-RestMethod -Uri ($infoUrl + "&format=json") -Headers $h -ErrorAction Stop
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $raw = [System.Text.Encoding]::UTF8.GetBytes("XGRlBW9FXlekgbPrRHuSiA" + $j.path.Substring(1) + $j.s)
        $sig = [System.BitConverter]::ToString($md5.ComputeHash($raw)).Replace("-","").ToLower()
        return "https://" + $j.host + "/get-mp3/" + $sig + "/" + $j.ts + $j.path
    } catch {
        return $null
    }
}

# --- Main ---

$token = Get-Token
$h     = Get-Headers $token

Clear-Host
Write-Host ""
Write-Host "  Proverka avtorizatsii..."

try {
    $status = Call-Api "/account/status" $h
    $uid    = $status.account.uid
    $uname  = $status.account.displayName
    Write-Host "  OK! Privet, $uname (uid=$uid)"
} catch {
    Write-Host "  Oshibka avtorizatsii. Proverte token."
    Read-Host "  Enter"
    exit
}

Write-Host ""
Write-Host "  Zagruzhayu pleylist..."

$playlist = $null
foreach ($ep in @("/users/$uid/playlists/$PLAYLIST`?rich-tracks=true", "/users/$uid/playlists/$PLAYLIST")) {
    try { $playlist = Call-Api $ep $h; if ($playlist) { break } } catch {}
}

if (-not $playlist) {
    Write-Host "  Ne udalos zaguzit pleylist."
    Read-Host "  Enter"
    exit
}

$tracks = $playlist.tracks
$title  = Clean-Name $playlist.title
$total  = $tracks.Count

Write-Host "  Pleylist: $title ($total trekov)"

$outDir = Join-Path $OUTPUT $title
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Write-Host "  Sohranyayu v: $outDir"
Write-Host ""

$ok = 0; $skip = 0; $fail = 0

for ($i = 0; $i -lt $total; $i++) {
    $entry  = $tracks[$i]
    $tr     = if ($entry.track) { $entry.track } else { $entry }
    $tid    = $tr.id
    $tt     = $tr.title
    $artist = ($tr.artists | ForEach-Object { $_.name }) -join ", "
    $num    = ([string]($i + 1)).PadLeft(3, '0')
    $fname  = Clean-Name ("$num. $artist - $tt")
    $dest   = Join-Path $outDir ($fname + ".mp3")

    Write-Host ("  [" + ($i+1) + "/$total] $artist - $tt") -NoNewline

    if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) {
        Write-Host " (skip)"
        $skip++
        continue
    }

    try {
        $infos = Call-Api "/tracks/$tid/download-info" $h
        $best  = $infos | Where-Object { $_.codec -eq "mp3" } | Sort-Object { [int]$_.bitrateInKbps } -Descending | Select-Object -First 1
        if (-not $best) { $best = $infos | Select-Object -First 1 }

        $url = Get-DirectUrl $best.downloadInfoUrl $h
        if (-not $url) { throw "no url" }

        Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        Write-Host " OK"
        $ok++
    } catch {
        Write-Host " FAIL"
        $fail++
    }

    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "  ================================================"
Write-Host ("  Gotovo!  Skachano: $ok  |  Skip: $skip  |  Oshibok: $fail")
Write-Host "  Fayly: $outDir"
Write-Host "  ================================================"
Write-Host ""
Read-Host "  Nazhmite Enter dlya vyhoda"
