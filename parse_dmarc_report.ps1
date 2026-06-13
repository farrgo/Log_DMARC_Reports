# This script parses DMARC aggregate report XML files from a specified path and extracts relevant information into PowerShell objects.
# It supports both individual XML files and directories containing multiple XML files, with an option to include subdirectories.
# The extracted data includes report metadata, policy settings, and per-record authentication results.

<# Define the script parameters.
 - Path: file or directory to search for DMARC XML files.
 - Recursive: include subdirectories when searching directories.
 - OutputCsv: optional path to write extracted results as CSV.
 - DeleteOriginal: optional flag to delete original XML files after parsing.
 #>
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$Path = ".",

    [Parameter(Position = 1, Mandatory = $false)]
    [object]$Recursive = $false,

    [Parameter(Position = 2, Mandatory = $false)]
    [string]$OutputCsv,

    [Parameter(Position = 3, Mandatory = $false)]
    [object]$DeleteOriginal = $false
)

function Convert-ToBool {
    
    <#
        Converts various input types to a boolean value.
        Supports boolean, switch, integer, and common string representations of truthy values.
    #>
    
    param (
        [object]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [switch]) {
        return [bool]$Value
    }

    if ($Value -is [int]) {
        return $Value -ne 0
    }

    $stringValue = $Value.ToString().Trim().ToLowerInvariant()
    return $stringValue -in @('true', '1', 'yes', 'y')
}

function Get-NslookupResult {
    <#
        Runs NSLOOKUP for a given IP address and returns the first resolved name or the raw output if no PTR exists.
    #>
    param (
        [string]$IpAddress
    )

    # If no IP was provided, return an empty string instead of attempting NSLOOKUP.
    if ([string]::IsNullOrWhiteSpace($IpAddress)) {
        return ''
    }

    try {
        # Run the NSLOOKUP command and capture both stdout and stderr.
        $output = & nslookup $IpAddress 2>&1

        # If NSLOOKUP returned a non-zero exit code, return the raw output as an error indicator.
        if ($LASTEXITCODE -ne 0) {
            return ($output -join ' | ')
        }

        # Search the NSLOOKUP output for a PTR record name line.
        $nameMatch = $output | Select-String -Pattern 'Name:\s*(.+)$' | Select-Object -First 1

        # If a Name line was found, return the resolved hostname.
        if ($nameMatch) {
            return $nameMatch.Matches[0].Groups[1].Value.Trim()
        }

        # If no Name line was found, return the full raw NSLOOKUP output.
        return ($output -join ' | ')
    } catch {
        # If the NSLOOKUP command itself throws an exception, return that message.
        return "NSLOOKUP failed: $($_.Exception.Message)"
    }
}

function Get-DmarcXmlFiles {
    <#
        Returns XML file objects from the provided path.
        If the path is a directory, it finds all XML files under it.
        If the path is a file, it validates that the file has an .xml extension.
    #>
    param (
        [string]$Path,
        [switch]$Recursive
    )

    # Verify the provided path exists before attempting to enumerate files.
    if (Test-Path $Path) {
        $item = Get-Item -Path $Path

        # If the path is a folder, enumerate XML files under it.
        if ($item.PSIsContainer) {
            Get-ChildItem -Path $Path -Filter *.xml -File -Recurse:$Recursive
        } else {

            # If the path is a file, only return it when it is an XML file.
            if ($item.Extension -eq '.xml') {
                @($item)
            } else {
                Write-Error "Path is a file but not an XML file: $Path"
                return @()
            }
        }
    } else {
 
        # Report an error when the provided path does not exist.
        Write-Error "Path not found: $Path"
        return @()
    }
}

function Convert-DmarcReport {
    <#
        Parses a DMARC aggregate report XML document and converts each record into a PowerShell object.
        This function extracts metadata, policy settings, and per-record authentication results.
    #>
    param (
        [xml]$Xml,
        [string]$SourceFile
    )

    # Extract the top-level report metadata and published policy section.
    $reportMetadata = $Xml.feedback.report_metadata
    $policyPublished = $Xml.feedback.policy_published

    # Use a portable Unix epoch value instead of the PS 7+ UnixEpoch property.
    $unixEpoch = [datetime]'1970-01-01T00:00:00Z'

    # Build a base ordered property bag with values from the report header.
    $baseProperties = [ordered]@{
        SourceFile = $SourceFile
        ReportId = $reportMetadata.report_id
        OrgName = $reportMetadata.org_name
        OrgEmail = $reportMetadata.email
        ExtraContactInfo = $reportMetadata.extra_contact_info
        DateRangeBegin = $unixEpoch.AddSeconds([int]$reportMetadata.date_range.begin).ToLocalTime()
        DateRangeEnd = $unixEpoch.AddSeconds([int]$reportMetadata.date_range.end).ToLocalTime()
        PolicyDomain = $policyPublished.domain
        PolicyAdkim = $policyPublished.adkim
        PolicyAspf = $policyPublished.aspf
        PolicyP = $policyPublished.p
        PolicySp = $policyPublished.sp
        PolicyPct = $policyPublished.pct
        PolicyNp = $policyPublished.np
    }

    # Loop through each record element in the DMARC XML report.
    foreach ($record in $Xml.feedback.record) {
        $row = $record.row
        $identifiers = $record.identifiers
        $authResults = $record.auth_results

        # Create temporary arrays for SPF and DKIM auth details in this record.
        $spfResults = @()
        $dkimResults = @()

        # Collect all SPF auth result entries for this record.
        foreach ($spf in $authResults.spf) {
            $spfResults += "{0}:{1}" -f $spf.domain, $spf.result
        }

        # Collect all DKIM auth result entries for this record.
        foreach ($dkim in $authResults.dkim) {
            $dkimResults += "{0}:{1}" -f $dkim.domain, $dkim.result
        }

        # Copy the shared report metadata into a new ordered property bag.
        $properties = [ordered]@{}
        foreach ($item in $baseProperties.GetEnumerator()) {
            $properties[$item.Key] = $item.Value
        }

        # Add per-record fields to the copied property bag.
        $properties.SourceIp = $row.source_ip
        $properties.Nslookup = Get-NslookupResult -IpAddress $row.source_ip
        $properties.Count = [int]$row.count
        $properties.Disposition = $row.policy_evaluated.disposition
        $properties.DkimResult = $row.policy_evaluated.dkim
        $properties.SpfResult = $row.policy_evaluated.spf
        $properties.HeaderFrom = $identifiers.header_from
        $properties.SpfAuth = ($spfResults -join '; ')
        $properties.DkimAuth = ($dkimResults -join '; ')
        
        # Output a custom object for each parsed record.
        [pscustomobject]$properties
    }
}


# Convert incoming parameters to boolean flags for shell compatibility.
$RecursiveFlag = Convert-ToBool -Value $Recursive
$DeleteOriginalFlag = Convert-ToBool -Value $DeleteOriginal

# Find the XML files to process from the provided path.
$files = Get-DmarcXmlFiles -Path $Path -Recursive:$RecursiveFlag

# If no XML files were found, print a message and exit with failure.
if (-not $files) {
    Write-Host "No DMARC XML files found at path: $Path"
    exit 1
}

# Initialize an array for the parsed result objects.
$results = @()

# Parse each found XML file and append the resulting objects.
foreach ($file in $files) {
    try {
        Write-Host "Parsing: $($file.FullName)"
        $xml = [xml](Get-Content -Path $file.FullName -ErrorAction Stop)
        $results += Convert-DmarcReport -Xml $xml -SourceFile $file.FullName

        # Delete the original XML file if the DeleteOriginal flag is set.
        if ($DeleteOriginalFlag) {
            
            # Store the path to the file before deletion, excluding the file name.
            $fileDirectory = Split-Path -Path $file.FullName -Parent

            # Delete the file.
            Remove-Item -Path $file.FullName -Force
            Write-Host "Deleted original file: $($file.FullName)"

            # If the directory is now empty after deletion and is not the directory given as this script's parameter, remove it as well.
            if (-not (Get-ChildItem -Path $fileDirectory -File) -and $fileDirectory -ne $Path) {
                Remove-Item -Path $fileDirectory -Force
                Write-Host "Deleted empty directory: $fileDirectory"
            }
        }

    } catch {
        # If parsing fails for a file, log a warning and continue to the next file.
        Write-Warning "Failed to parse $($file.FullName): $($_.Exception.Message)"
    }
}

# Fail if parsing completed but no records were produced.
if ($results.Count -eq 0) {
    Write-Error "No DMARC report records were parsed."
    exit 1
}

# Display the parsed results in a formatted table.
$results | Format-Table -AutoSize

# If an output CSV path was supplied, write the parsed results to that file.
if ($OutputCsv) {
    try {
        $csvExists = Test-Path -Path $OutputCsv

        if ($csvExists) {
            # If the CSV file already exists, append to it without writing a new header.
            $results | Export-Csv -Path $OutputCsv -NoTypeInformation -Force -Append
            Write-Host "Appended results to existing CSV: $OutputCsv"

        } else {
            # If the CSV file does not exist, create it and write the results with a header.
            $results | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
            Write-Host "Exported results to $OutputCsv"
        }
    } catch {
        Write-Error "Failed to export CSV: $_"
    }
}
