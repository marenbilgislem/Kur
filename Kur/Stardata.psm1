#Requires -Version 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:CalismaKok    = "C:\ProgramData\Maren"
$script:ConfigDosyasi = Join-Path $script:CalismaKok "config.txt"
$script:LogDosyasi    = Join-Path $script:CalismaKok "ajan.log"
$script:LokPcAdi      = $env:COMPUTERNAME.Trim()

$script:VarsayilanConfig = [ordered]@{
    RepoApiUrl        = "https://api.github.com/repos/marenbilgislem/Kur/contents/Kur"
    StardataUrl       = "https://raw.githubusercontent.com/marenbilgislem/Kur/main/Stardata.psm1"
    YonetimUrl        = "https://raw.githubusercontent.com/marenbilgislem/Kur/main/Yonetim.ps1"
    IndirmeKlasor     = "C:\ProgramData\Maren\Temp"
    ProgramKontrolAdi = "7-Zip"
}

function Initialize-MarenAjan {
    if (-not (Test-Path -Path $script:CalismaKok)) {
        New-Item -Path $script:CalismaKok -ItemType Directory -Force | Out-Null
    }
    $cfg = Get-MarenConfig
    if (-not (Test-Path -Path $cfg.IndirmeKlasor)) {
        New-Item -Path $cfg.IndirmeKlasor -ItemType Directory -Force | Out-Null
    }
    return $cfg
}

function Save-MarenConfig {
    param([hashtable]$Cfg)
    $satirlar = foreach ($k in $script:VarsayilanConfig.Keys) {
        "{0}={1}" -f $k, $Cfg[$k]
    }
    Set-Content -Path $script:ConfigDosyasi -Value $satirlar -Encoding UTF8
}

function Get-MarenConfig {
    if (-not (Test-Path -Path $script:CalismaKok)) {
        New-Item -Path $script:CalismaKok -ItemType Directory -Force | Out-Null
    }

    $cfg = @{}
    foreach ($k in $script:VarsayilanConfig.Keys) {
        $cfg[$k] = $script:VarsayilanConfig[$k]
    }

    if (-not (Test-Path -Path $script:ConfigDosyasi)) {
        Save-MarenConfig -Cfg $cfg
        return $cfg
    }

    try {
        $satirlar = Get-Content -Path $script:ConfigDosyasi -Encoding UTF8 -ErrorAction Stop
        foreach ($satir in $satirlar) {
            $s = $satir.Trim()
            if ([string]::IsNullOrWhiteSpace($s) -or $s.StartsWith("#") -or $s.StartsWith(";")) {
                continue
            }
            $parca = $s -split "=", 2
            if ($parca.Count -eq 2) {
                $anahtar = $parca[0].Trim()
                $deger   = $parca[1].Trim()
                if ($script:VarsayilanConfig.Contains($anahtar)) {
                    $cfg[$anahtar] = $deger
                }
            }
        }
    } catch {
        $yedek = Join-Path $script:CalismaKok ("config_bozuk_{0}.bak" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Copy-Item -Path $script:ConfigDosyasi -Destination $yedek -Force -ErrorAction SilentlyContinue
        Save-MarenConfig -Cfg $cfg
    }

    return $cfg
}

function Write-MarenLog {
    param([string]$Mesaj)
    if (-not (Test-Path -Path $script:CalismaKok)) {
        New-Item -Path $script:CalismaKok -ItemType Directory -Force | Out-Null
    }
    $satir = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $script:LokPcAdi, $Mesaj
    Add-Content -Path $script:LogDosyasi -Value $satir -Encoding UTF8
    Write-Host $satir
}

function Send-MarenTelegram {
    param(
        [Parameter(Mandatory)][string]$BotToken,
        [Parameter(Mandatory)][string]$ChatId,
        [string]$Metin
    )
    if ([string]::IsNullOrWhiteSpace($Metin)) { $Metin = "(Bos cikti)" }
    if ($Metin.Length -gt 3800) {
        $Metin = $Metin.Substring(0, 3800) + "`n...(kirpildi)"
    }

    $uri  = "https://api.telegram.org/bot$BotToken/sendMessage"
    $body = @{
        chat_id = $ChatId
        text    = $Metin
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 20 | Out-Null
    } catch {
        Write-MarenLog "Telegram gonderim hatasi: $($_.Exception.Message)"
    }
}

function Get-InstalledProgramsList {
    $regYollar = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $programlar = Get-ItemProperty -Path $regYollar -ErrorAction SilentlyContinue |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.DisplayName) -and
            ([string]$_.SystemComponent -ne "1")
        } |
        Select-Object -ExpandProperty DisplayName |
        Sort-Object -Unique

    return @($programlar)
}

function Test-SingleTargetInstalled {
    param([string]$Hedef)
    if ([string]::IsNullOrWhiteSpace($Hedef)) { return $false }

    $h = $Hedef.Trim()

    if ($h -match "^[A-Za-z]:\\" -or $h.StartsWith("\\")) {
        if (Test-Path -Path $h) { return $true }
    }

    $regYollar = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $kayit = Get-ItemProperty -Path $regYollar -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$h*") } |
        Select-Object -First 1

    if ($kayit) { return $true }

    $kokDizinler = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($kok in $kokDizinler) {
        $eslesen = Get-ChildItem -Path $kok -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$h*" } |
            Select-Object -First 1
        if ($eslesen) { return $true }
    }

    return $false
}

function Test-ProgramInstalledList {
    param([string]$ProgramListesiMetni)
    if ([string]::IsNullOrWhiteSpace($ProgramListesiMetni)) { return $null }

    $hedefler = @($ProgramListesiMetni -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($hedefler.Count -eq 0) { return $null }

    $bulunanlar = @()
    $bulunamayanlar = @()

    foreach ($hedef in $hedefler) {
        if (Test-SingleTargetInstalled -Hedef $hedef) {
            $bulunanlar += $hedef
        } else {
            $bulunamayanlar += $hedef
        }
    }

    return [PSCustomObject]@{
        TumuKuruldu    = ($bulunamayanlar.Count -eq 0)
        HerhangiKurulu = ($bulunanlar.Count -gt 0)
        Bulunanlar     = $bulunanlar
        Bulunamayanlar = $bulunamayanlar
    }
}

function Invoke-DurumKomutu {
    param(
        [Parameter(Mandatory = $false)]
        $Config
    )

    $pcAdi     = $env:COMPUTERNAME
    $kullanici = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }

    $windowsMetni   = "Bilinmiyor"
    $calismaSuresi = "Bilinmiyor"
    $ramMetni       = "Bilinmiyor"
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

        $cv = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
        $surumEtiketi = if ($cv -and $cv.DisplayVersion) { $cv.DisplayVersion } else { $os.Version }
        $windowsMetni = "{0} ({1}, Build {2})" -f $os.Caption.Trim(), $surumEtiketi, $os.BuildNumber

        $fark = (Get-Date) - $os.LastBootUpTime
        $calismaSuresi = "{0}g {1}s {2}d" -f $fark.Days, $fark.Hours, $fark.Minutes

        $toplamGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $bosGb    = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $ramMetni = "$bosGb GB bos / $toplamGb GB"
    } catch {}

    $ipListesi = @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.InterfaceAlias -notlike "*Loopback*"
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    )
    $ipMetni = if ($ipListesi.Count -gt 0) { $ipListesi -join ", " } else { "Bulunamadi" }

    $cDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $diskMetni = if ($cDisk) {
        $bosC    = [math]::Round($cDisk.FreeSpace / 1GB, 1)
        $toplamC = [math]::Round($cDisk.Size / 1GB, 1)
        "$bosC GB bos / $toplamC GB (C:)"
    } else {
        "Bilinmiyor"
    }

    $satirlar = @(
        "Durum Raporu"
        "PC Adi: $pcAdi"
        "Kullanici: $kullanici"
        "Windows: $windowsMetni"
        "IPv4: $ipMetni"
        "Uptime: $calismaSuresi"
        "RAM: $ramMetni"
        "Disk: $diskMetni"
        "Saat: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    )

    return ($satirlar -join "`n")
}
function Invoke-ConfigKomutu {
    param(
        [hashtable]$Config,
        [string]$KomutGovdesi
    )
    $cfgParca = if ([string]::IsNullOrWhiteSpace($KomutGovdesi)) { @() } else { $KomutGovdesi -split "\s+", 2 }
    $altKomut = if ($cfgParca.Count -ge 1) { $cfgParca[0].ToLower() } else { "goster" }
    $deger    = if ($cfgParca.Count -ge 2) { $cfgParca[1].Trim() } else { "" }

    switch ($altKomut) {
        "goster" {
            return "[$($script:LokPcAdi)] config.txt:`nRepoApiUrl=$($Config.RepoApiUrl)`nStardataUrl=$($Config.StardataUrl)`nYonetimUrl=$($Config.YonetimUrl)`nIndirmeKlasor=$($Config.IndirmeKlasor)`nProgramKontrolAdi=$($Config.ProgramKontrolAdi)"
        }
        "url" {
            if ([string]::IsNullOrWhiteSpace($deger)) { return "[$($script:LokPcAdi)] Kullanim: /config [PC_ADI] url <yeni_url>" }
            $Config.RepoApiUrl = $deger
            Save-MarenConfig -Cfg $Config
            Write-MarenLog "RepoApiUrl guncellendi: $deger"
            return "[$($script:LokPcAdi)] RepoApiUrl guncellendi:`n$deger"
        }
        "stardataurl" {
            if ([string]::IsNullOrWhiteSpace($deger)) { return "[$($script:LokPcAdi)] Kullanim: /config [PC_ADI] stardataurl <raw_url>" }
            $Config.StardataUrl = $deger
            Save-MarenConfig -Cfg $Config
            Write-MarenLog "StardataUrl guncellendi: $deger"
            return "[$($script:LokPcAdi)] StardataUrl guncellendi:`n$deger"
        }
        "yonetimurl" {
            if ([string]::IsNullOrWhiteSpace($deger)) { return "[$($script:LokPcAdi)] Kullanim: /config [PC_ADI] yonetimurl <raw_url>" }
            $Config.YonetimUrl = $deger
            Save-MarenConfig -Cfg $Config
            Write-MarenLog "YonetimUrl guncellendi: $deger"
            return "[$($script:LokPcAdi)] YonetimUrl guncellendi:`n$deger"
        }
        "klasor" {
            if ([string]::IsNullOrWhiteSpace($deger)) { return "[$($script:LokPcAdi)] Kullanim: /config [PC_ADI] klasor <yeni_klasor>" }
            if (-not (Test-Path -Path $deger)) { New-Item -Path $deger -ItemType Directory -Force | Out-Null }
            $Config.IndirmeKlasor = $deger
            Save-MarenConfig -Cfg $Config
            Write-MarenLog "IndirmeKlasor guncellendi: $deger"
            return "[$($script:LokPcAdi)] IndirmeKlasor guncellendi:`n$deger"
        }
        "program" {
            if ($deger -ieq "temizle" -or $deger -ieq "yok") {
                $deger = ""
                $Config.ProgramKontrolAdi = $deger
                Save-MarenConfig -Cfg $Config
                Write-MarenLog "ProgramKontrolAdi temizlendi."
                return "[$($script:LokPcAdi)] ProgramKontrolAdi temizlendi (Kapali)."
            }

            if ([string]::IsNullOrWhiteSpace($deger) -or ($deger.ToLower() -in @("liste", "hepsi", "tumu", "tümü"))) {
                $liste = Get-InstalledProgramsList
                if (-not $liste -or $liste.Count -eq 0) {
                    return "[$($script:LokPcAdi)] Kurulu program bulunamadi."
                }
                Write-MarenLog "Kurulu program listesi alindi (Adet: $($liste.Count))."
                return "[$($script:LokPcAdi)] Kurulu Programlar ($($liste.Count))`n- " + ($liste -join "`n- ")
            }

            $Config.ProgramKontrolAdi = $deger
            Save-MarenConfig -Cfg $Config
            Write-MarenLog "ProgramKontrolAdi guncellendi: '$deger'"
            return "[$($script:LokPcAdi)] ProgramKontrolAdi guncellendi: $deger"
        }
        "sifirla" {
            foreach ($k in $script:VarsayilanConfig.Keys) { $Config[$k] = $script:VarsayilanConfig[$k] }
            Save-MarenConfig -Cfg $Config
            Write-MarenLog "Config varsayilan ayarlara sifirlandi."
            return "[$($script:LokPcAdi)] Config varsayilan ayarlara sifirlandi."
        }
        default {
            return "[$($script:LokPcAdi)] Kullanilabilir: /config [goster | url <adres> | stardataurl <url> | yonetimurl <url> | klasor <yol> | program <liste|ad1,ad2|temizle> | sifirla]"
        }
    }
}

function Invoke-IndirKomutu {
    param([hashtable]$Config)
    try {
        if (-not (Test-Path -Path $Config.IndirmeKlasor)) {
            New-Item -Path $Config.IndirmeKlasor -ItemType Directory -Force | Out-Null
        }
        $headers = @{
            "User-Agent" = "MarenAjan-PS"
            "Accept"     = "application/vnd.github+json"
        }
        $kayitlar = Invoke-RestMethod -Uri $Config.RepoApiUrl -Headers $headers -TimeoutSec 25
        $dosyalar = @($kayitlar | Where-Object { $_.type -eq "file" -and $_.download_url })

        if ($dosyalar.Count -eq 0) {
            return "[$($script:LokPcAdi)] Kaynakta indirilecek dosya bulunamadi."
        }

        $inenler = @()
        foreach ($d in $dosyalar) {
            $hedef = Join-Path -Path $Config.IndirmeKlasor -ChildPath $d.name
            Invoke-WebRequest -Uri $d.download_url -OutFile $hedef -UseBasicParsing -TimeoutSec 60
            $inenler += $d.name
            Write-MarenLog "Indirildi: $hedef"
        }

        return "[$($script:LokPcAdi)] $($inenler.Count) dosya indirildi -> $($Config.IndirmeKlasor)`n- " + ($inenler -join "`n- ")
    } catch {
        Write-MarenLog "Indirme hatasi: $($_.Exception.Message)"
        return "[$($script:LokPcAdi)] Indirme HATA: $($_.Exception.Message)"
    }
}

function Invoke-PaketKomutu {
    param(
        [Parameter(Mandatory = $false)]
        $Config,
        [Parameter(Mandatory = $false)]
        [string]$KomutGovdesi = ""
    )

    $lokPc = $env:COMPUTERNAME.Trim()
    $satirlar = [System.Collections.Generic.List[string]]::new()
    $satirlar.Add("[$lokPc] Paket Islemi Basladi")

    $adimlar = @("Indir", "Kur", "Temizle")
    if (-not [string]::IsNullOrWhiteSpace($KomutGovdesi)) {
        $ilkKelime = ($KomutGovdesi.Trim() -split "\s+")[0].ToLower()
        switch ($ilkKelime) {
            "indir"   { $adimlar = @("Indir") }
            "kur"     { $adimlar = @("Kur") }
            "temizle" { $adimlar = @("Temizle") }
            "tamkur"  { $adimlar = @("Indir", "Kur", "Temizle") }
        }
    }

    foreach ($adim in $adimlar) {
        switch ($adim) {
            "Indir" {
                try {
                    $cmd = Get-Command -Name "Invoke-IndirKomutu" -ErrorAction SilentlyContinue
                    if ($cmd) {
                        $c = if ($cmd.Parameters.ContainsKey("KomutGovdesi")) {
                            Invoke-IndirKomutu -Config $Config -KomutGovdesi $KomutGovdesi
                        } else {
                            Invoke-IndirKomutu -Config $Config
                        }
                        $cMetin = if ([string]::IsNullOrWhiteSpace([string]$c)) { "Tamamlandi" } else { ([string]$c).Trim() }
                        $satirlar.Add("1) Indir: $cMetin")
                    } else {
                        $satirlar.Add("1) Indir: Invoke-IndirKomutu bulunamadi (Atlandi)")
                    }
                } catch {
                    $satirlar.Add("1) Indir HATA: $($_.Exception.Message)")
                    break
                }
            }

            "Kur" {
                try {
                    $cmd = Get-Command -Name "Invoke-KurKomutu" -ErrorAction SilentlyContinue
                    if ($cmd) {
                        $c = if ($cmd.Parameters.ContainsKey("KomutGovdesi")) {
                            Invoke-KurKomutu -Config $Config -KomutGovdesi $KomutGovdesi
                        } else {
                            Invoke-KurKomutu -Config $Config
                        }
                        $cMetin = if ([string]::IsNullOrWhiteSpace([string]$c)) { "Tamamlandi" } else { ([string]$c).Trim() }
                        $satirlar.Add("2) Kur: $cMetin")
                    } else {
                        $satirlar.Add("2) Kur: Invoke-KurKomutu bulunamadi (Atlandi)")
                    }
                } catch {
                    $satirlar.Add("2) Kur HATA: $($_.Exception.Message)")
                    break
                }
            }

            "Temizle" {
                try {
                    $cmd = Get-Command -Name "Invoke-TemizleKomutu" -ErrorAction SilentlyContinue
                    if ($cmd) {
                        $c = if ($cmd.Parameters.ContainsKey("KomutGovdesi")) {
                            Invoke-TemizleKomutu -Config $Config -KomutGovdesi $KomutGovdesi
                        } else {
                            Invoke-TemizleKomutu -Config $Config
                        }
                        $cMetin = if ([string]::IsNullOrWhiteSpace([string]$c)) { "Tamamlandi" } else { ([string]$c).Trim() }
                        $satirlar.Add("3) Temizle: $cMetin")
                    } else {
                        $tempYol = Join-Path "C:\ProgramData\Maren" "Temp"
                        if (Test-Path -Path $tempYol) {
                            Get-ChildItem -Path $tempYol -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        $satirlar.Add("3) Temizle: Temp klasoru temizlendi")
                    }
                } catch {
                    $satirlar.Add("3) Temizle HATA: $($_.Exception.Message)")
                }
            }
        }
    }

    $satirlar.Add("[$lokPc] Paket Islemi Bitti")
    return ($satirlar -join "`n")
}

function Invoke-UpdateKomutu {
    param(
        [Parameter(Mandatory = $false)]
        $Config,
        [Parameter(Mandatory = $false)]
        [string]$KomutGovdesi = ""
    )

    $lokPc   = $env:COMPUTERNAME.Trim()
    $rapor   = [System.Collections.Generic.List[string]]::new()
    $rapor.Add("[$lokPc] Windows Update (/update - Istege Bagli Dahil)")

    $sadeceKontrol = $false
    if (-not [string]::IsNullOrWhiteSpace($KomutGovdesi)) {
        if ($KomutGovdesi.Trim().ToLower() -in @("kontrol", "durum", "check", "list")) {
            $sadeceKontrol = $true
        }
    }

    try {
        $session  = New-Object -ComObject "Microsoft.Update.Session"
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true

        Write-MarenLog "Windows Update taramasi basladi (istege bagli dahil)..."
        $aramaSonucu = $searcher.Search("IsInstalled=0")
        $bulunanlar  = @($aramaSonucu.Updates)

        if ($bulunanlar.Count -eq 0) {
            $rapor.Add("- Durum: Sistem guncel, bekleyen (zorunlu veya istege bagli) guncelleme yok.")
            Write-MarenLog "Bekleyen Windows Update bulunamadi."
            return ($rapor -join "`n")
        }

        $istegeBagliSayisi = @($bulunanlar | Where-Object { -not $_.AutoSelectOnWebSites -or $_.BrowseOnly }).Count
        $rapor.Add("- Bulunan Guncelleme: $($bulunanlar.Count) adet (Tahmini istege bagli/secmeli: $istegeBagliSayisi)")

        foreach ($u in $bulunanlar) {
            $etiket = if (-not $u.AutoSelectOnWebSites) { "[Istege Bagli]" } else { "[Standart]" }
            $rapor.Add("  * $etiket $($u.Title)")
        }

        if ($sadeceKontrol) {
            $rapor.Add("- Mod: Yalnizca kontrol yapildi, indirme/kurulum yapilmadi.")
            return ($rapor -join "`n")
        }

        $indirilecekKoleksiyon = New-Object -ComObject "Microsoft.Update.UpdateColl"
        foreach ($u in $bulunanlar) {
            if ($u.EulaAccepted -eq $false) {
                $u.AcceptEula()
            }
            if ($u.IsDownloaded -eq $false) {
                [void]$indirilecekKoleksiyon.Add($u)
            }
        }

        if ($indirilecekKoleksiyon.Count -gt 0) {
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $indirilecekKoleksiyon
            $indirSonuc = $downloader.Download()
            $rapor.Add("- Indirme Sonucu Kodu: $($indirSonuc.ResultCode) ($($indirilecekKoleksiyon.Count) paket)")
        } else {
            $rapor.Add("- Indirme: Paketler zaten indirilmis.")
        }

        $kurulacakKoleksiyon = New-Object -ComObject "Microsoft.Update.UpdateColl"
        foreach ($u in $bulunanlar) {
            if ($u.IsDownloaded) {
                [void]$kurulacakKoleksiyon.Add($u)
            }
        }

        if ($kurulacakKoleksiyon.Count -gt 0) {
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $kurulacakKoleksiyon
            $kurSonuc = $installer.Install()
            $rapor.Add("- Kurulum Sonucu Kodu: $($kurSonuc.ResultCode)")
            $rapor.Add("- Yeniden Baslatma Gerekli mi: $($kurSonuc.RebootRequired)")
        } else {
            $rapor.Add("- Kurulum: Kurulabilir durumda paket bulunamadi.")
        }

        Write-MarenLog "Windows Update islemi tamamlandi."
    } catch {
        $hata = $_.Exception.Message
        Write-MarenLog "Windows Update hatasi: $hata"
        $rapor.Add("- HATA: $hata")
    }

    return ($rapor -join "`n")
}

function Invoke-TamKurKomutu {
    param(
        [Parameter(Mandatory = $false)]
        $Config,
        [Parameter(Mandatory = $false)]
        [string]$KomutGovdesi = ""
    )

    return (Invoke-PaketKomutu -Config $Config -KomutGovdesi $KomutGovdesi)
}

function Invoke-KurKomutu {
    param([hashtable]$Config)
    if (-not (Test-Path -Path $Config.IndirmeKlasor)) {
        return "[$($script:LokPcAdi)] Klasor bulunamadi: $($Config.IndirmeKlasor)"
    }

    $kurDosya = Get-ChildItem -Path $Config.IndirmeKlasor -File |
        Where-Object { $_.BaseName -ieq "Kur" } |
        Sort-Object @{ Expression = {
            switch ($_.Extension.ToLower()) {
                ".bat" { 1 }
                ".cmd" { 2 }
                ".ps1" { 3 }
                ".exe" { 4 }
                ""     { 5 }
                default { 9 }
            }
        } } |
        Select-Object -First 1

    if (-not $kurDosya) {
        return "[$($script:LokPcAdi)] $($Config.IndirmeKlasor) icinde 'Kur' dosyasi bulunamadi."
    }

    Unblock-File -Path $kurDosya.FullName -ErrorAction SilentlyContinue
    Write-MarenLog "Kur dosyasi calistiriliyor: $($kurDosya.FullName)"

    try {
        $ext = $kurDosya.Extension.ToLower()
        if ($ext -eq ".ps1") {
            $cikti = (powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$($kurDosya.FullName)`"" 2>&1 | Out-String)
            $kod = $LASTEXITCODE
        } elseif ($ext -in @(".bat", ".cmd", "")) {
            $cikti = (cmd.exe /c "`"$($kurDosya.FullName)`"" 2>&1 | Out-String)
            $kod = $LASTEXITCODE
        } elseif ($ext -eq ".exe") {
            $proc = Start-Process -FilePath $kurDosya.FullName -PassThru -Wait -NoNewWindow
            $kod = $proc.ExitCode
            $cikti = "EXE calistirildi."
        } else {
            $cikti = (cmd.exe /c "`"$($kurDosya.FullName)`"" 2>&1 | Out-String)
            $kod = $LASTEXITCODE
        }

        $kurulumDurum = ""
        if (-not [string]::IsNullOrWhiteSpace($Config.ProgramKontrolAdi)) {
            $sonuc = Test-ProgramInstalledList -ProgramListesiMetni $Config.ProgramKontrolAdi
            if ($null -ne $sonuc) {
                $bStr = if ($sonuc.Bulunanlar.Count -gt 0) { $sonuc.Bulunanlar -join ", " } else { "Yok" }
                $yStr = if ($sonuc.Bulunamayanlar.Count -gt 0) { $sonuc.Bulunamayanlar -join ", " } else { "Yok" }
                $kurulumDurum = "`nKontrol -> Kurulu: [$bStr] | Eksik: [$yStr]"
            }
        }

        Write-MarenLog "Kur tamamlandi (Kod: $kod): $($kurDosya.Name)"
        $mesaj = "[$($script:LokPcAdi)] Dosya: $($kurDosya.Name) | Kod: $kod$kurulumDurum"
        if ($cikti.Trim()) { $mesaj += "`n" + $cikti.Trim() }
        return $mesaj
    } catch {
        Write-MarenLog "Kur calistirma hatasi: $($_.Exception.Message)"
        return "[$($script:LokPcAdi)] Kur HATA: $($_.Exception.Message)"
    }
}

function Invoke-TemizleKomutu {
    param([hashtable]$Config)
    if (-not (Test-Path -Path $Config.IndirmeKlasor)) {
        New-Item -Path $Config.IndirmeKlasor -ItemType Directory -Force | Out-Null
        return "[$($script:LokPcAdi)] Temp klasoru olusturuldu (zaten bostu): $($Config.IndirmeKlasor)"
    }

    try {
        Get-ChildItem -Path $Config.IndirmeKlasor -Force | Remove-Item -Recurse -Force -ErrorAction Stop
        Write-MarenLog "Temp icerigi temizlendi: $($Config.IndirmeKlasor)"
        return "[$($script:LokPcAdi)] Temp icerigi temizlendi: $($Config.IndirmeKlasor)"
    } catch {
        Write-MarenLog "Temizleme hatasi: $($_.Exception.Message)"
        return "[$($script:LokPcAdi)] Temizleme HATA: $($_.Exception.Message)"
    }
}

function Invoke-CmdKomutu {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KomutGovdesi = ""
    )

    $lokPc = $env:COMPUTERNAME.Trim()
    if ([string]::IsNullOrWhiteSpace($KomutGovdesi)) {
        return "[$lokPc] Kullanim: /cmd <komut>"
    }

    try {
        Write-MarenLog "CMD calistiriliyor: $KomutGovdesi"
        $cikti = cmd.exe /c $KomutGovdesi 2>&1 | Out-String
        $metin = $cikti.Trim()
        if ([string]::IsNullOrWhiteSpace($metin)) {
            $metin = "(Cikti yok / Tamamlandi)"
        }
        if ($metin.Length -gt 3500) {
            $metin = $metin.Substring(0, 3500) + "`n... (cikti kirpildi)"
        }
        return "[$lokPc] CMD:`n$metin"
    } catch {
        return "[$lokPc] CMD HATA: $($_.Exception.Message)"
    }
}

function Invoke-ShellKomutu {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KomutGovdesi = ""
    )

    $lokPc = $env:COMPUTERNAME.Trim()
    if ([string]::IsNullOrWhiteSpace($KomutGovdesi)) {
        return "[$lokPc] Kullanim: /shell <powershell komutu>"
    }

    try {
        Write-MarenLog "PowerShell calistiriliyor: $KomutGovdesi"
        $scriptBlock = [scriptblock]::Create($KomutGovdesi)
        $cikti = & $scriptBlock 2>&1 | Out-String
        $metin = $cikti.Trim()
        if ([string]::IsNullOrWhiteSpace($metin)) {
            $metin = "(Cikti yok / Tamamlandi)"
        }
        if ($metin.Length -gt 3500) {
            $metin = $metin.Substring(0, 3500) + "`n... (cikti kirpildi)"
        }
        return "[$lokPc] SHELL:`n$metin"
    } catch {
        return "[$lokPc] SHELL HATA: $($_.Exception.Message)"
    }
}

function Update-MarenKodDosyasi {
    param(
        [Parameter(Mandatory)][string]$HedefDosya,
        [Parameter(Mandatory)][string]$KaynakUrl,
        [string]$BotToken = "",
        [string]$AllowedChatId = ""
    )
    if ([string]::IsNullOrWhiteSpace($KaynakUrl)) {
        return "[$($script:LokPcAdi)] Kaynak URL bos."
    }

    $gecici = Join-Path $script:CalismaKok ("{0}.new" -f [System.IO.Path]::GetFileName($HedefDosya))
    $yedek  = "$HedefDosya.bak"

    try {
        $headers = @{ "User-Agent" = "MarenAjan-PS" }
        Invoke-WebRequest -Uri $KaynakUrl -Headers $headers -OutFile $gecici -UseBasicParsing -TimeoutSec 45

        if (-not (Test-Path -Path $gecici) -or ((Get-Item -Path $gecici).Length -lt 50)) {
            throw "Indirilen dosya bos veya gecersiz."
        }

        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($gecici, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors -and $errors.Count -gt 0) {
            $hataOzet = ($errors | Select-Object -First 3 | ForEach-Object { $_.Message }) -join " | "
            throw "Sozdizimi hatasi: $hataOzet"
        }

        $icerik = Get-Content -Path $gecici -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($BotToken) -and $BotToken -notmatch 'BURAYA_BOT_TOKEN_YAZ') {
            $icerik = $icerik.Replace("BURAYA_BOT_TOKEN_YAZ", $BotToken)
        }
        if (-not [string]::IsNullOrWhiteSpace($AllowedChatId) -and $AllowedChatId -notmatch 'BURAYA_KENDI_CHAT_ID_YAZ') {
            $icerik = $icerik.Replace("BURAYA_KENDI_CHAT_ID_YAZ", $AllowedChatId)
        }
        Set-Content -Path $gecici -Value $icerik -Encoding UTF8

        if (Test-Path -Path $HedefDosya) {
            Copy-Item -Path $HedefDosya -Destination $yedek -Force
        }
        Move-Item -Path $gecici -Destination $HedefDosya -Force

        Write-MarenLog "Guncellendi: $HedefDosya ($KaynakUrl)"
        return "[$($script:LokPcAdi)] Guncellendi: $HedefDosya (Yedek: $yedek)"
    } catch {
        if (Test-Path -Path $gecici) {
            Remove-Item -Path $gecici -Force -ErrorAction SilentlyContinue
        }
        Write-MarenLog "Guncelleme hatasi ($HedefDosya): $($_.Exception.Message)"
        return "[$($script:LokPcAdi)] Guncelleme HATA ($HedefDosya): $($_.Exception.Message)"
    }
}

function Invoke-DurKomutu {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KomutGovdesi = ""
    )

    $lokPc = $env:COMPUTERNAME.Trim()
    $durdurulan = [System.Collections.Generic.List[string]]::new()
    $hatalar    = [System.Collections.Generic.List[string]]::new()

    $hedefAdlar = @("powershell", "pwsh", "cmd", "msiexec", "wusa")
    if (-not [string]::IsNullOrWhiteSpace($KomutGovdesi)) {
        $filtre = ($KomutGovdesi.Trim() -split "\s+")[0].ToLower()
        if ($filtre -in @("ps", "powershell", "pwsh")) {
            $hedefAdlar = @("powershell", "pwsh")
        } elseif ($filtre -eq "cmd") {
            $hedefAdlar = @("cmd")
        }
    }

    try {
        $tumSurecler = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.ProcessId -ne $PID -and
            $_.ProcessId -ne 0 -and
            $_.ProcessId -ne 4 -and
            ($_.Name -replace "\.exe$", "").ToLower() -in $hedefAdlar
        }

        foreach ($proc in $tumSurecler) {
            # Mevcut tlg.ps1 ajan surecini koru
            if ($proc.CommandLine -and $proc.CommandLine -match "tlg\.ps1") {
                continue
            }

            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                $durdurulan.Add("$($proc.Name) (PID: $($proc.ProcessId))")
            } catch {
                $hatalar.Add("$($proc.Name) [PID: $($proc.ProcessId)]: $($_.Exception.Message)")
            }
        }
    } catch {
        return "[$lokPc] /dur HATA: $($_.Exception.Message)"
    }

    Write-MarenLog "/dur komutu calisti. Durdurulan: $($durdurulan.Count) | Hata: $($hatalar.Count)"

    $rapor = [System.Collections.Generic.List[string]]::new()
    $rapor.Add("[$lokPc] /dur Islemi Tamamlandi")
    if ($durdurulan.Count -gt 0) {
        $rapor.Add("- Durdurulan ($($durdurulan.Count)): $($durdurulan -join ', ')")
    } else {
        $rapor.Add("- Durdurulan islem bulunamadi.")
    }
    if ($hatalar.Count -gt 0) {
        $rapor.Add("- Durdurulamayan ($($hatalar.Count)): $($hatalar -join ' | ')")
    }

    return ($rapor -join "`n")
}

Export-ModuleMember -Function *