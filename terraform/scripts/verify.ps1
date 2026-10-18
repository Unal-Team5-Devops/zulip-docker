$ErrorActionPreference = "Stop"
param(
    [string]$Prefix = "zulip-dev",
    [string]$Url = $Url
)
$app = "$Prefix-zulip"
$dataContainers = @("$Prefix-postgres", "$Prefix-memcached", "$Prefix-rabbitmq", "$Prefix-redis")
$containers = @($app) + $dataContainers

Write-Host "== Container status ==" -ForegroundColor Cyan
foreach ($name in $containers) {
    $status = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $name 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Container $name not found. Run terraform apply first."
        exit 1
    }
    Write-Host ("{0,-20} {1}" -f $name, $status)
    if ($name -ne $app -and $status -ne "healthy") {
        Write-Warning "$name has not reported healthy yet. Inspect with: docker logs $name"
    }
    if ($name -eq $app -and $status -ne "running") {
        Write-Warning "Zulip is not running. Inspect with: docker logs $app"
    }
}

Write-Host "`n== Only Zulip publishes ports ==" -ForegroundColor Cyan
foreach ($name in $dataContainers) {
    $published = docker port $name 2>$null
    if ($published) {
        Write-Error "$name unexpectedly publishes ports to the host: $published"
        exit 1
    }
    Write-Host "$name : no published host ports"
}
Write-Host "$app port mappings:"
docker port $app

Write-Host "`n== HTTP/TLS response ==" -ForegroundColor Cyan
try {
    $statusCode = & curl.exe -k -sS -o NUL -w "%{http_code}" $Url
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "No HTTPS response yet. Check the hosts file, port 443 and docker logs $app."
    }
    else {
        Write-Host "HTTPS response code: $statusCode"
        Write-Host "A response code proves that the HTTP server responds; finish realm creation/login for a functional check."
    }
}
catch {
    Write-Warning "Could not execute curl.exe. Try manually: curl.exe -k -I $Url"
}

Write-Host "`n== Docker networks and volumes ==" -ForegroundColor Cyan
docker network inspect "$Prefix-frontend" --format '{{.Name}} internal={{.Internal}} containers={{len .Containers}}'
docker network inspect "$Prefix-backend" --format '{{.Name}} internal={{.Internal}} containers={{len .Containers}}'
docker volume ls --filter "name=$Prefix-"
