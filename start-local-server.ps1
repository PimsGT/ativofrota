$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
$port = 4173
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
$listener.Start()
Write-Host "AtivoFrota disponível em http://localhost:$port/"
Write-Host "Pressione Ctrl+C para encerrar."
$types = @{
  '.html'='text/html; charset=utf-8'; '.js'='text/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8';
  '.json'='application/json'; '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.svg'='image/svg+xml';
  '.pdf'='application/pdf'; '.ico'='image/x-icon'
}
function Send-Response($stream, [int]$status, [string]$contentType, [byte[]]$body) {
  $reason = if ($status -eq 200) { 'OK' } elseif ($status -eq 404) { 'Not Found' } else { 'Forbidden' }
  $header = "HTTP/1.1 $status $reason`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  $stream.Write($body, 0, $body.Length)
  $stream.Flush()
}
try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 4096, $true)
      $requestLine = $reader.ReadLine()
      while (($line = $reader.ReadLine()) -and $line -ne '') { }
      $relative = 'index.html'
      if ($requestLine -match '^GET\s+([^\s]+)') {
        $rawPath = ($Matches[1] -split '\?')[0]
        $relative = [Uri]::UnescapeDataString($rawPath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'index.html' }
      }
      $relative = $relative -replace '/', '\\'
      if ($relative.Contains('..')) { Send-Response $stream 403 'text/plain' ([Text.Encoding]::UTF8.GetBytes('Forbidden')) }
      else {
        $file = Join-Path $root $relative
        if (Test-Path $file -PathType Leaf) {
          $body = [IO.File]::ReadAllBytes((Resolve-Path $file))
          $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
          $contentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
          Send-Response $stream 200 $contentType $body
        } else { Send-Response $stream 404 'text/plain' ([Text.Encoding]::UTF8.GetBytes('Not found')) }
      }
    } catch { }
    finally { if ($stream) { $stream.Dispose() }; $client.Dispose() }
  }
} finally { $listener.Stop() }
