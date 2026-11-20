@echo off
chcp 65001 >nul

set "9223691015:AAGcK5n_X7rJ5sAbcQxuDmaJo9JAImH1sK8"
set "5286193818"

echo Kurulum Yapiliyor Lutfen Bekleyiniz...
"C:\ProgramData\Temp\7z-x64.exe" /S
set "DURUM=%ERRORLEVEL%"
echo Kurulum Yapilidi.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$t = '%TOKEN%'; $c = '%CHAT_ID%'; $code = '%DURUM%';" ^
  "$msg = \"Bilgisayar: $env:COMPUTERNAME`nDosya: Kur.bat | Cikis Kodu: $code`nKurulum Yapildi.\";" ^
  "$body = @{ chat_id = $c; text = $msg } | ConvertTo-Json;" ^
  "try { Invoke-RestMethod -Uri \"https://api.telegram.org/bot$t/sendMessage\" -Method Post -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null; Write-Host 'Telegram bildirimi gonderildi.' } catch { Write-Host 'Telegram bildirimi gonderilemedi.' }"
