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
# Get all archive files in the directory.
$archiveFiles = Get-ChildItem -Path $Directory -Include *.zip, *.tar.gz, *.tar.bz2 -File

# Loop through the collection of archive files and extract each one.
foreach ($file in $archiveFiles) {

    # Define the file path, name, and destination path for extraction.
    $filePath = $file.FullName
    $fileName = $file.Name
    $destinationPath = Join-Path -Path $Directory -ChildPath ($file.BaseName)

    Write-Host "Extracting: $fileName to $destinationPath"

    try {
 
        if ($file.Extension -eq ".zip") {
            # Extract .zip files.
            Expand-Archive -Path $filePath -DestinationPath $destinationPath -Force
        
        } elseif ($file.Extension -eq ".gz" -and $file.BaseName.EndsWith(".tar")) {
            # Extract .tar.gz files.
            tar -xzf $filePath -C $Directory

        } elseif ($file.Extension -eq ".bz2" -and $file.BaseName.EndsWith(".tar")) {
            # Extract .tar.bz2 files.
            tar -xjf $filePath -C $Directory
        
        } else {
            Write-Warning "Unsupported file type: $fileName"
        }
   
        # Delete the original archive file if the $DeleteOriginal parameter is set to $true.
        if ($DeleteOriginal) {
            Remove-Item -Path $filePath -Force
            Write-Host "Deleted original file: $fileName"
        }

    } catch {
        Write-Error "Failed to extract: $fileName. Error: $_"
    }
}