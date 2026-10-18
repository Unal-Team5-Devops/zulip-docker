$ErrorActionPreference = "Stop"
$containers = @(
    "zulip-app",
    "zulip-database",
    "zulip-memcached",
    "zulip-rabbitmq",
    "zulip-redis"
)

Write-Host "== Container status ==" -ForegroundColor Cyan
foreach ($name in $containers) {
    $status = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $name 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Container $name not found. Run terraform apply first."
        exit 1
    }
    Write-Host ("{0,-20} {1}" -f $name, $status)
    if ($name -ne "zulip-app" -and $status -ne "healthy") {
        Write-Warning "$name has not reported healthy yet. Inspect with: docker logs $name"
    }
    if ($name -eq "zulip-app" -and $status -ne "running") {
        Write-Warning "Zulip is not running. Inspect with: docker logs zulip-app"
    }
}

Write-Host "`n== Only Zulip publishes ports ==" -ForegroundColor Cyan
foreach ($name in @("zulip-database", "zulip-memcached", "zulip-rabbitmq", "zulip-redis")) {
    $published = docker port $name 2>$null
    if ($published) {
        Write-Error "$name unexpectedly publishes ports to the host: $published"
        exit 1
    }
    Write-Host "$name : no published host ports"
}
Write-Host "zulip-app port mappings:"
docker port zulip-app

Write-Host "`n== HTTP/TLS response ==" -ForegroundColor Cyan
try {
    $statusCode = & curl.exe -k -sS -o NUL -w "%{http_code}" "https://zulip.localhost/"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "No HTTPS response yet. Check the hosts file, port 443 and docker logs zulip-app."
    }
    else {
        Write-Host "HTTPS response code: $statusCode"
        Write-Host "A response code proves that the HTTP server responds; finish realm creation/login for a functional check."
    }
}
catch {
    Write-Warning "Could not execute curl.exe. Try manually: curl.exe -k -I https://zulip.localhost/"
}

Write-Host "`n== Docker networks and volumes ==" -ForegroundColor Cyan
docker network inspect zulip-frontend --format '{{.Name}} internal={{.Internal}} containers={{len .Containers}}'
docker network inspect zulip-backend --format '{{.Name}} internal={{.Internal}} containers={{len .Containers}}'
docker volume ls --filter name=zulip-
