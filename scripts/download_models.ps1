[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AssetsDir = "app\src\main\assets"
if (-Not (Test-Path -Path $AssetsDir)) {
    New-Item -ItemType Directory -Force -Path $AssetsDir | Out-Null
}

Write-Host "Downloading Silero VAD model..."
$VadUrl = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
Invoke-WebRequest -Uri $VadUrl -OutFile "$AssetsDir\silero_vad.onnx"

Write-Host "Model placeholder setup complete."
Write-Host "Note: Due to size constraints, full Sherpa-ONNX streaming Zipformer models (~50MB) and VITS models should be manually downloaded and extracted into $AssetsDir."
