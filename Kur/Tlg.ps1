#Requires -Version 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BotToken        = "9223691015:AAGcK5n_X7rJ5sAbcQxuDmaJo9JAImH1sK8"
$AllowedChatId   = "5286193818"
$CalismaKok      = "C:\ProgramData\Maren"
$StardataDosyasi = Join-Path $CalismaKok "Stardata.psm1"
$YonetimDosyasi  = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $CalismaKok "Yonetim.ps1" }
$OffsetDosyasi   = Join-Path $CalismaKok "offset.txt"
$LokPcAdi        = $env:COMPUTERNAME.Trim()

if (-not (Test-Path -Path $CalismaKok)) {
    New-Item -Path $CalismaKok -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -Path $StardataDosyasi)) {
    Write-Error "Stardata modulu bulunamadi: $StardataDosyasi"
    exit 1
}

try {
    Remove-Module -Name "Stardata" -Force -ErrorAction SilentlyContinue
    Import-Module -Name $StardataDosyasi -Force -ErrorAction Stop
} catch {
    Write-Error "Stardata modulu yuklenemedi: $($_.Exception.Message)"
    exit 1
}

$Config = Initialize-MarenAjan

$sureDakika  = 15
$bitisZamani = (Get-Date).AddMinutes($sureDakika)
Write-MarenLog "tlg dinleyicisi 15 dk dongude basladi. Bitis: $($bitisZamani.ToString('HH:mm:ss'))"

while ((Get-Date) -lt $bitisZamani) {
    $offset = 0
    if (Test-Path -Path $OffsetDosyasi) {
        $rawOffset = (Get-Content -Path $OffsetDosyasi -Raw -ErrorAction SilentlyContinue).Trim()
        if ($rawOffset -match "^\d+$") { $offset = [long]$rawOffset }
    }

    $updatesUrl = "https://api.telegram.org/bot$BotToken/getUpdates?timeout=10"
    if ($offset -gt 0) { $updatesUrl += "&offset=$offset" }

    try {
        $resp = Invoke-RestMethod -Uri $updatesUrl -Method Get -TimeoutSec 25
    } catch {
        Write-MarenLog "getUpdates hatasi: $($_.Exception.Message)"
        if ((Get-Date) -lt $bitisZamani) { Start-Sleep -Seconds 5 }
        continue
    }

    if ($resp.ok -and $resp.result) {
        foreach ($upd in $resp.result) {
            $yeniOffset = [long]$upd.update_id + 1
            Set-Content -Path $OffsetDosyasi -Value $yeniOffset -NoNewline -Encoding ASCII

            $msg = $upd.message
            if (-not $msg -or -not $msg.text) { continue }

            if ([string]$msg.chat.id -ne [string]$AllowedChatId) {
                Write-MarenLog "Yetkisiz Chat ID reddedildi: $($msg.chat.id)"
                continue
            }

            $metin = $msg.text.Trim()
            Write-MarenLog "Komut alindi: $metin"

            $parcalar = $metin -split "\s+"
            $anaKomut = $parcalar[0].ToLower()

            if ($parcalar.Count -ge 2 -and $parcalar[1] -match "^[A-Za-z0-9_-]+$" -and $parcalar[1] -notlike "/*") {
                if ($parcalar[1] -ine $LokPcAdi) {
                    Write-MarenLog "Komut baska PC icin ($($parcalar[1])), atlandi."
                    continue
                }
                $komutGovdesi = if ($parcalar.Count -ge 3) { ($parcalar[2..($parcalar.Count - 1)] -join " ").Trim() } else { "" }
            } else {
                $komutGovdesi = if ($parcalar.Count -ge 2) { ($parcalar[1..($parcalar.Count - 1)] -join " ").Trim() } else { "" }
            }

            $yanit = switch ($anaKomut) {
                "/durum"      { Invoke-DurumKomutu -Config $Config }
                "/config"     { Invoke-ConfigKomutu -Config $Config -KomutGovdesi $komutGovdesi }
                "/indir"      { Invoke-IndirKomutu -Config $Config }
                "/kur"        { Invoke-KurKomutu -Config $Config }
                "/temizle"    { Invoke-TemizleKomutu -Config $Config }
                "/calistir"   { Invoke-CalistirKomutu -KomutGovdesi $komutGovdesi }
                "/pcguncelle" { Invoke-PcGuncelleKomutu }
                "/guncelle" {
                    $hedefTip = "stardata"
                    $ozelUrl  = ""
                    if (-not [string]::IsNullOrWhiteSpace($komutGovdesi)) {
                        $gParca = $komutGovdesi -split "\s+", 2
                        if ($gParca[0].ToLower() -in @("stardata", "yonetim", "hepsi")) {
                            $hedefTip = $gParca[0].ToLower()
                            if ($gParca.Count -ge 2) { $ozelUrl = $gParca[1].Trim() }
                        } else {
                            $ozelUrl = $komutGovdesi.Trim()
                        }
                    }

                    switch ($hedefTip) {
                        "yonetim" {
                            $url = if ($ozelUrl) { $ozelUrl } else { $Config.YonetimUrl }
                            Update-MarenKodDosyasi -HedefDosya $YonetimDosyasi -KaynakUrl $url -BotToken $BotToken -AllowedChatId $AllowedChatId
                        }
                        "hepsi" {
                            $r1 = Update-MarenKodDosyasi -HedefDosya $StardataDosyasi -KaynakUrl $Config.StardataUrl -BotToken $BotToken -AllowedChatId $AllowedChatId
                            $r2 = Update-MarenKodDosyasi -HedefDosya $YonetimDosyasi -KaynakUrl $Config.YonetimUrl -BotToken $BotToken -AllowedChatId $AllowedChatId
                            "$r1`n$r2"
                        }
                        default {
                            $url = if ($ozelUrl) { $ozelUrl } else { $Config.StardataUrl }
                            Update-MarenKodDosyasi -HedefDosya $StardataDosyasi -KaynakUrl $url -BotToken $BotToken -AllowedChatId $AllowedChatId
                        }
                    }
                }
                default {
                    "[$LokPcAdi] Bilinmeyen komut. Kullanilabilir: /durum, /config, /guncelle, /pcguncelle, /indir, /kur, /calistir, /temizle"
                }
            }

            Send-MarenTelegram -BotToken $BotToken -ChatId $AllowedChatId -Metin $yanit
        }
    }

    if ((Get-Date) -lt $bitisZamani) {
        Start-Sleep -Seconds 2
    }
}

Write-MarenLog "15 dakikalik dinleme suresi doldu, cikiliyor."