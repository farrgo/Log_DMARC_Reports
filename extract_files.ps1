# This script extracts any archive files in the directory specified by the parameter $Directory.
# It supports .zip, .tar.gz, and .tar.bz2 files.
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
            $_.Name.ToLowerInvariant().EndsWith('.tar.gz') -or
            $_.Name.ToLowerInvariant().EndsWith('.tar.bz2')
        )
    }
}

# Function to extract .zip files using the Shell.Application COM object.
function Expand-ZipArchive {
    param (
        [string]$ZipPath,
        [string]$DestinationPath
    )

    # Make sure the destination directory exists. Create it if it doesn't.
    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath | Out-Null
    }

    # Use the Shell.Application COM object to extract the ZIP file. This method is compatible with Windows and does not require external tools.
    $shell = New-Object -ComObject Shell.Application
    $zip = $shell.NameSpace($ZipPath)
    if (-not $zip) {
        throw "Unable to open ZIP archive: $ZipPath"
    }

    $destination = $shell.NameSpace($DestinationPath)
    if (-not $destination) {
        throw "Unable to open destination folder: $DestinationPath"
    }

    # Extract the contents of the ZIP file to the destination folder. The 0x10 flag suppresses progress dialogs and error messages.
    $destination.CopyHere($zip.Items(), 0x10)
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