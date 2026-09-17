$rootDir = "C:\AMPACIMON"

$paths = @(
    "adr2",
    "adr2\apcm-keycloak-bundle",
    "adr2\apcm-nginx-bundle",
    "adr2\apcm-payara-bundle",
    "csvFiles",
    "GitBash",
    "installFiles",
    "installFiles\ADR-Bundle",
    "installFiles\DB-Installer",
    "installFiles\ipConvOPC",
    "installFiles\JDK",
    "installFiles\profiles",
    "installFiles\tools",
    "installFiles\war-ear-files",
    "IPCOMM",
    "Java",
    "Java\jdk17",
    "MongoCompass",
    "MongoDB",
    "pgAdmin",
    "PostgreSQL"
)

Write-Host "Creating AMPACIMON directory structure..."

# Ensure root directory exists
if (-not (Test-Path -Path $rootDir)) {
    Write-Host "Creating root directory: $rootDir"
    try {
        New-Item -ItemType Directory -Path $rootDir -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create root directory $rootDir. Error: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "Root directory $rootDir already exists."
}

foreach ($relPath in $paths) {
    $fullPath = Join-Path -Path $rootDir -ChildPath $relPath
    if (-not (Test-Path -Path $fullPath)) {
        Write-Host "Creating: $fullPath"
        try {
            New-Item -ItemType Directory -Path $fullPath -ErrorAction Stop | Out-Null
        } catch {
            Write-Error "Failed to create directory $fullPath. Error: $($_.Exception.Message)"
        }
    } else {
        Write-Host "Skipping (exists): $fullPath"
    }
}

Write-Host "Directory structure creation completed."
