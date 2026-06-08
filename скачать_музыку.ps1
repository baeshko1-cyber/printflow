# Yandex Music Downloader
# Правая кнопка на файле -> "Выполнить с помощью PowerShell"

$ErrorActionPreference = "SilentlyContinue"
$PLAYLIST = "lk.799fa788-940c-4b6c-9d1c-7316144b09f7"
$OUTPUT   = "$HOME\Desktop\Музыка"

function Get-Token {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host "     Шаг 1 из 2 — Получаем токен" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Сейчас откроется браузер." -ForegroundColor White
    Write-Host ""
    Write-Host "  Что нужно сделать:" -ForegroundColor Cyan
    Write-Host "   1. В браузере нажмите кнопку  [ Войти ]  или  [ Разрешить ]" -ForegroundColor White
    Write-Host "   2. Страница обновится — СРАЗУ нажмите Ctrl+A в адресной строке" -ForegroundColor White
    Write-Host "      чтобы выделить весь адрес, потом Ctrl+C чтобы скопировать" -ForegroundColor White
    Write-Host "   3. Вернитесь сюда и нажмите Ctrl+V (вставить)" -ForegroundColor White
    Write-Host ""
    Read-Host "  Нажмите Enter чтобы открыть браузер"

    Start-Process "https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d"

    Write-Host ""
    $raw = Read-Host "  Вставьте содержимое адресной строки и нажмите Enter"

    if ($raw -match "access_token=([A-Za-z0-9_\-]+)") {
        return $matches[1]
    }
    # Может быть просто токен без URL
    if ($raw -match "^[A-Za-z0-9_\-]{30,}$") {
        return $raw.Trim()
    }
    Write-Host ""
    Write-Host "  Не удалось найти токен в строке. Попробуйте ещё раз." -ForegroundColor Red
    Write-Host "  Убедитесь что скопировали ВЕСЬ текст из адресной строки." -ForegroundColor Red
    Write-Host ""
    Read-Host "  Нажмите Enter для выхода"
    exit
}

function Get-ApiHeaders($token) {
    return @{
        "Authorization"          = "OAuth $token"
        "X-Yandex-Music-Client"  = "YandexMusicAndroid/23020251"
        "Accept"                 = "application/json"
    }
}

function Invoke-YmApi($path, $headers) {
    $r = Invoke-RestMethod -Uri "https://api.music.yandex.net$path" `
                           -Headers $headers -Method Get -ErrorAction Stop
    return $r.result
}

function Get-DirectUrl($infoUrl, $headers) {
    try {
        $j = Invoke-RestMethod -Uri ($infoUrl + "&format=json") -Headers $headers -ErrorAction Stop
        $sign = [System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes("XGRlBW9FXlekgbPrRHuSiA" + $j.path.Substring(1) + $j.s)
            )
        ).Replace("-","").ToLower()
        return "https://$($j.host)/get-mp3/$sign/$($j.ts)$($j.path)"
    } catch {
        # XML fallback
        $xml = Invoke-RestMethod -Uri $infoUrl -Headers $headers -ErrorAction Stop
        $ns  = @{d = "http://www.yandex.ru/music/download-info"}
        $host2 = (Select-Xml -Xml $xml -XPath "//d:host" -Namespace $ns).Node.InnerText
        $path2 = (Select-Xml -Xml $xml -XPath "//d:path" -Namespace $ns).Node.InnerText
        $ts2   = (Select-Xml -Xml $xml -XPath "//d:ts"   -Namespace $ns).Node.InnerText
        $s2    = (Select-Xml -Xml $xml -XPath "//d:s"    -Namespace $ns).Node.InnerText
        $sign  = [System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes("XGRlBW9FXlekgbPrRHuSiA" + $path2.Substring(1) + $s2)
            )
        ).Replace("-","").ToLower()
        return "https://$host2/get-mp3/$sign/$ts2$path2"
    }
}

# ─── Старт ────────────────────────────────────────────────────────────────────

$token = Get-Token
$h     = Get-ApiHeaders $token

Clear-Host
Write-Host ""
Write-Host "  Проверяю авторизацию..." -ForegroundColor Cyan

try {
    $status = Invoke-YmApi "/account/status" $h
    $uid    = $status.account.uid
    $name   = $status.account.displayName
    Write-Host "  Привет, $name! (uid=$uid)" -ForegroundColor Green
} catch {
    Write-Host "  Ошибка авторизации. Попробуйте заново." -ForegroundColor Red
    Read-Host "  Enter для выхода"
    exit
}

Write-Host ""
Write-Host "  Загружаю плейлист..." -ForegroundColor Cyan

$playlist = $null
foreach ($endpoint in @(
    "/users/$uid/playlists/$PLAYLIST`?rich-tracks=true",
    "/users/$uid/playlists/$PLAYLIST"
)) {
    try { $playlist = Invoke-YmApi $endpoint $h; break } catch {}
}

if (-not $playlist) {
    # Попробуем через метод POST для нескольких плейлистов
    try {
        $body = "{`"kinds`":`"$PLAYLIST`",`"mixed`":false,`"richTracks`":true}"
        $r    = Invoke-RestMethod -Uri "https://api.music.yandex.net/users/$uid/playlists" `
                                  -Headers $h -Method Post -Body $body `
                                  -ContentType "application/json" -ErrorAction Stop
        $playlist = $r.result[0]
    } catch {}
}

if (-not $playlist) {
    Write-Host "  Не удалось загрузить плейлист. Нет доступа или плейлист не существует." -ForegroundColor Red
    Read-Host "  Enter для выхода"
    exit
}

$tracks    = $playlist.tracks
$title     = $playlist.title
$total     = $tracks.Count
Write-Host "  Плейлист: $title ($total треков)" -ForegroundColor Green

$outDir = Join-Path $OUTPUT ($title -replace '[\\/:*?"<>|]','_')
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Write-Host "  Сохраняю в: $outDir" -ForegroundColor White
Write-Host ""

$ok = 0; $skip = 0; $fail = 0

for ($i = 0; $i -lt $tracks.Count; $i++) {
    $entry  = $tracks[$i]
    $track  = if ($entry.track) { $entry.track } else { $entry }
    $tid    = $track.id
    $ttitle = $track.title
    $artist = ($track.artists | ForEach-Object { $_.name }) -join ", "
    $name   = "$($i+1).".PadLeft(4,'0').Substring(0,4) + " $artist — $ttitle"
    $name   = $name -replace '[\\/:*?"<>|]','_'
    $dest   = Join-Path $outDir "$name.mp3"

    Write-Host "  [$($i+1)/$total] $artist — $ttitle" -NoNewline

    if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) {
        Write-Host " (пропущен)" -ForegroundColor DarkGray
        $skip++
        continue
    }

    try {
        $infos = Invoke-YmApi "/tracks/$tid/download-info" $h
        $best  = $infos | Where-Object { $_.codec -eq "mp3" } |
                 Sort-Object { $_.bitrateInKbps } -Descending |
                 Select-Object -First 1
        if (-not $best) { $best = $infos | Select-Object -First 1 }

        $url = Get-DirectUrl $best.downloadInfoUrl $h
        Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host " ОШИБКА" -ForegroundColor Red
        $fail++
    }

    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host "  Готово! Скачано: $ok  |  Пропущено: $skip  |  Ошибок: $fail" -ForegroundColor Yellow
Write-Host "  Файлы: $outDir" -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Нажмите Enter для выхода"
