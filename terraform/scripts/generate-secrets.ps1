$ErrorActionPreference = "Stop"
$secretsDir = Join-Path $PSScriptRoot "..\secrets"
New-Item -ItemType Directory -Force -Path $secretsDir | Out-Null

$names = @(
    "zulip__postgres_password",
    "zulip__memcached_password",
    "zulip__rabbitmq_password",
    "zulip__redis_password",
    "zulip__secret_key",
    "zulip__email_password"
)
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    foreach ($name in $names) {
        $bytes = New-Object byte[] 32
        $random.GetBytes($bytes)
        $value = [BitConverter]::ToString($bytes).Replace("-", "").ToLowerInvariant()
        $path = Join-Path $secretsDir $name
        [System.IO.File]::WriteAllText($path, $value, $utf8NoBom)
        Write-Host "Secret file created: secrets/$name"
    }
}
finally {
    $random.Dispose()
}
Write-Host "The secret values were not printed. Do not commit the secrets directory."
