# This script extracts any archive files in the directory specified by the parameter $Directory.
# It supports .zip, .gz, .tar.gz, and .tar.bz2 files.
# If the optional parameter $DeleteOriginal is set to $true, the original archive files will be deleted after extraction.

param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$Directory = ".",

    [Parameter(Mandatory = $false)]
    [bool]$DeleteOriginal = $false
)

# Check if the directory exists.
if (-not (Test-Path $Directory)) {
    Write-Error "Directory not found: $Directory"
    exit 1
}

# Function to get all archive files in the specified directory.
function Get-ArchiveFiles {
    param (
        [string]$DirectoryPath
    )

    $path = Join-Path -Path $DirectoryPath -ChildPath '*'
    Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Where-Object {
        -not $_.PSIsContainer -and (
            $_.Name.ToLowerInvariant().EndsWith('.zip') -or
            $_.Name.ToLowerInvariant().EndsWith('.gz') -or
            $_.Name.ToLowerInvariant().EndsWith('.tar.gz') -or
            $_.Name.ToLowerInvariant().EndsWith('.tar.bz2')
        )
    }
}

# Function to extract .zip files in a cross-platform way.
function Expand-ZipArchive {
    param (
        [string]$ZipPath,
        [string]$DestinationPath
    )

    # Make sure the destination directory exists. Create it if it doesn't.
    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath | Out-Null
    }

    # Prefer the built-in Expand-Archive cmdlet when available, because it works across PowerShell Core on Windows, macOS, and Linux.
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        try {
            Expand-Archive -Path $ZipPath -DestinationPath $DestinationPath -Force
            return
        } catch {
            Write-Warning "Expand-Archive failed for ${ZipPath}: $($_.Exception.Message)"
        }
    }

    # If Expand-Archive is unavailable or fails, use .NET ZipFile as a fallback.
    try {
        if (-not ([System.Type]::GetType('System.IO.Compression.ZipFile'))) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinationPath)
        return
    } catch {
        Write-Warning "Attempt to extract ZIP with .NET ZipFile failed: $($_.Exception.Message)"
    }

    # Last resort on Windows: use Shell.Application if available.
    if ($PSVersionTable.Platform -eq 'Win32NT' -and (Get-Command New-Object -ErrorAction SilentlyContinue)) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $zip = $shell.NameSpace($ZipPath)
            if (-not $zip) {
                throw "Unable to open ZIP archive: $ZipPath"
            }

            $destination = $shell.NameSpace($DestinationPath)
            if (-not $destination) {
                throw "Unable to open destination folder: $DestinationPath"
            }

            $destination.CopyHere($zip.Items(), 0x10)
            return
        } catch {
            throw "Unable to extract ZIP archive: $ZipPath. Error: $($_.Exception.Message)"
        }
    }

    throw "No supported ZIP extraction method is available on this platform. Please install PowerShell Core or ensure Expand-Archive / System.IO.Compression.FileSystem are available."
}

# Function to extract .gz files using gzip if available, falling back to .NET GZipStream.
function Expand-GzFile {
    param (
        [string]$GzPath,
        [string]$DestinationPath
    )

    # Check if the gzip command is available on the system (macOS, Linux, or Windows with gzip installed).
    if (Get-Command gzip -ErrorAction SilentlyContinue) {
        try {
            # Use gzip to extract the .gz file. The -d flag tells gzip to decompress the file, and -c outputs the result to stdout.
            gzip -d -c $GzPath > $DestinationPath
        } catch {
            throw "gzip command failed: $($_.Exception.Message)"
        }

    } else {
        try {
            # Fall back to .NET's GZipStream if gzip is not available. (This works on Windows without external tools).
            $sourceStream = [System.IO.File]::OpenRead($GzPath)
            $destinationStream = [System.IO.File]::Create($DestinationPath)
            $gzipStream = [System.IO.Compression.GZipStream]::new($sourceStream, [System.IO.Compression.CompressionMode]::Decompress)
            
            $gzipStream.CopyTo($destinationStream)
            
            $gzipStream.Dispose()
            $destinationStream.Dispose()
            $sourceStream.Dispose()
        } catch {
            throw "Failed to extract .gz file: $GzPath. Error: $($_.Exception.Message)"
        }
    }

}

# Get all archive files in the directory.
$archiveFiles = Get-ArchiveFiles -DirectoryPath $Directory

# Loop through the collection of archive files and extract each one.
foreach ($file in $archiveFiles) {

    # Define the file path, name, and destination path for extraction.
    $filePath = $file.FullName
    $fileName = $file.Name
    $destinationPath = Join-Path -Path $Directory -ChildPath ($file.BaseName)

    Write-Host "Extracting: $fileName to $destinationPath"

    try {
 
        if ($file.Name.ToLowerInvariant().EndsWith('.zip')) {
            # Extract .zip files.
            try {
                Expand-ZipArchive -ZipPath $filePath -DestinationPath $destinationPath
            } catch {
                throw $_
            }

        } elseif ($file.Name.ToLowerInvariant().EndsWith('.tar.gz')) {
            # Extract .tar.gz files if tar is available.
            if (Get-Command tar -ErrorAction SilentlyContinue) {
                tar -xzf $filePath -C $Directory
            } else {
                Write-Warning "tar command not found; cannot extract .tar.gz file: $fileName. Please install tar or extract this file manually."
            }

        } elseif ($file.Name.ToLowerInvariant().EndsWith('.tar.bz2')) {
            # Extract .tar.bz2 files if tar is available.
            if (Get-Command tar -ErrorAction SilentlyContinue) {
                tar -xjf $filePath -C $Directory
            } else {
                Write-Warning "tar command not found; cannot extract .tar.bz2 file: $fileName. Please install tar or extract this file manually."
            }
        
        } elseif ($file.Name.ToLowerInvariant().EndsWith('.gz')) {
            # Extract .gz files. .tar.gz files are handled by the tar command, so this case is for standalone .gz files.
            try {
                Expand-GzFile -GzPath $filePath -DestinationPath $destinationPath
            } catch {
                throw $_
            }
        
        } else {
            Write-Warning "Unsupported file type: $fileName."
        }
   
        # Delete the original archive file if the $DeleteOriginal parameter is set to $true.
        if ($DeleteOriginal) {
            Remove-Item -Path $filePath -Force
            Write-Host "Deleted original file: $fileName."
        }

    } catch {
        Write-Error "Failed to extract: $fileName. Error: $_"
    }
}