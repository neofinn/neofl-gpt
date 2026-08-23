$ErrorActionPreference = 'Stop'
$Model = 'qwen3:8b'
Write-Host 'NeoFLGPT Parallel - Local Brain Setup' -ForegroundColor Cyan

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
    Write-Host 'Ollama is not installed. Opening the official Windows installer page.' -ForegroundColor Yellow
    Start-Process 'https://ollama.com/download/windows'
    Write-Host 'Install Ollama, then rerun this setup script.'
    exit 2
}

try {
    $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
} catch {
    Write-Host 'Starting local Ollama server...' -ForegroundColor Yellow
    Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden
    Start-Sleep -Seconds 3
}

Write-Host "Pulling real local model $Model ..." -ForegroundColor Yellow
& ollama pull $Model
if ($LASTEXITCODE -ne 0) { throw "ollama pull failed with exit code $LASTEXITCODE" }

$dir = Join-Path $env:APPDATA 'NeoFLGPTParallel'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$config = @{ backend='ollama'; model=$Model; ollama_url='http://127.0.0.1:11434'; gguf_path='' } | ConvertTo-Json
Set-Content -Path (Join-Path $dir 'config.json') -Value $config -Encoding UTF8

Write-Host ''
Write-Host 'LOCAL BRAIN READY' -ForegroundColor Green
Write-Host "Model: $Model"
Write-Host 'Endpoint: http://127.0.0.1:11434'
