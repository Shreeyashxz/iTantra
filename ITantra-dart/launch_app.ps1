$exeDir = "d:\My FIles\Softwares\iTantra\ITantra-dart\build\windows\x64\runner\Release"
$exePath = Join-Path $exeDir "itantra_dart.exe"
Stop-Process -Name itantra_dart -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
$proc = Start-Process -FilePath $exePath -WorkingDirectory $exeDir -PassThru
Start-Sleep -Milliseconds 1500
if ($proc.HasExited) {
    Write-Host "App exited immediately! ExitCode: $($proc.ExitCode)"
} else {
    Write-Host "App is successfully running! PID: $($proc.Id)"
}
