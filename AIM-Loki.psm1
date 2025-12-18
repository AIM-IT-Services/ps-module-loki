# https://github.com/stefanes/PSLoki/blob/main/functions/Send-LokiLogEntry.ps1
function Send-LokiLog {
    param (
       [Parameter(Mandatory=$true)] 
       $URI,
       [Parameter(Mandatory=$true)]
       $Username,
       [Parameter(Mandatory=$true)]
       $Password,
       [hashtable[]] $Entries,
       [string]$LogLine,
       [hashtable] $Labels = @{
            aim_datasource  = "Script"
            aim_language    = "PowerShell"
            aim_application = "PowerShell Universal"
            level           = "info"
            aim_psmodule    = "-"
            aim_psfunction  = "-"
            aim_psfile      = "-"
        },
       [hashtable] $ExtraLabels
    )

    # Merge Labels
    if($ExtraLabels.Count -gt 0)
    {    
        foreach ($key in $ExtraLabels.Keys) {
            Write-Debug "Adding/Updating $($key) = $($ExtraLabels[$key])"
            $Labels[$key] = $ExtraLabels[$key]
        }
    } 

    # Construct Loki log entries to send
    $logEntries = @()
    foreach ($entry in $Entries) {
        $logEntryTime = if ($entry.time -gt 0) { $entry.time } else { Get-LokiTimestamp }
        $logEntries += @(, @(
                $logEntryTime
                $entry.line
            ))
    } 
    # If there is a single line
    if($LogLine)
    {
        $logEntryTime = Get-LokiTimestamp
        $logEntries += @(, @(
            $logEntryTime
            $LogLine
        ))
    }

    if($logEntries)
    { 

        Write-Debug "Entries: $($logEntries|ConvertTo-Json)"
        Write-Debug "Labels:  $($Labels|ConvertTo-Json)"
        # Setup HTTP 
        # Encode to Base64
        $pair = "$Username`:$Password"
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))

        # Add to headers
        $headers = @{
            "Authorization"    = "Basic $base64Auth"
            "Content-Type"     = "application/json"
        }    

        # Build SPLAT
        $splat = @{
            Method        = 'POST'
            Body          = @{
                streams = @(
                    @{
                        stream = $Labels
                        values = $logEntries
                    }
                )
            } | ConvertTo-Json -Depth 10
            Headers       = $headers
            TimeoutSec    = 60
            ErrorVariable = 'err'
        }

        $err = @( )
        # Make the request
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        Write-Debug "Posting:$($splat|ConvertTO-JSON -Depth 10)"
        Write-Debug "Posting to $URI"
        $response = Invoke-WebRequest @splat -Uri $URI
        $ErrorActionPreference = $eap    

        if ($err) {     
            Write-Error -Message $err.Message -Exception $err.InnerException -Category ConnectionError
            return $false
        } else {
            Write-Debug "$response"
            return $true
        }    
    } else {
        Write-Error -Message "No Log Lines"
        return $false        
    }
}

# https://raw.githubusercontent.com/stefanes/PSLoki/refs/heads/main/functions/Get-LokiTimestamp.ps1    
function Get-LokiTimestamp {
    <#
    .Synopsis
        Create a timestamp suitable for Loki log entries (Unix Epoch in nanoseconds).
    .Description
        Calling this function will return a timestamp suitable for Loki:
            - If a timestamp is provided it will be parsed and converted.
            - If no timestamp is provided the current date/time will be used.
    .Example
        $timestamp = Get-LokiTimestamp
        Write-Host "Current Unix Epoch is: $timestamp"
    .Example
        $timestamp = Get-LokiTimestamp -Timestamp '2022-09-07T14:51:57Z'
        Write-Host "Unix Epoch for 2022-09-07T14:51:57Z is: $timestamp"
    .Example
        $timestamp = Get-LokiTimestamp -Timestamp '1662562317000000000'
        Write-Host "Unix Epoch for 1662562317000000000 is, you guessed it...: $timestamp"
    .Example
        $timestamp = Get-LokiTimestamp -Date $([DateTime]::Parse('2022-09-07T14:51:57Z'))
        Write-Host "Unix Epoch for 2022-09-07T14:51:57Z is: $timestamp"
    .Link
        https://en.wikipedia.org/wiki/Unix_time
    #>
    param (
        # Specifies the timstamp to parse, if provided.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $Timestamp,

        # Specifies the date to parse, if provided.
        [Parameter(ValueFromPipelineByPropertyName)]
        [DateTime] $Date,

        # Specifies the number of seconds to add to the timestamp. The value can be negative or positive.
        [int] $AddSeconds = 0
    )

    begin {
        $dateFormat = 'yyyy-MM-ddTHH:mm:ssZ'
    }

    process {
        # Timestamp parameter provided
        if ($Timestamp) {
            # Check if already a Unix Epoch string
            if ($Timestamp -notmatch '^\d{10}(?:\d{9})?$') {
                $timestampAsDate = [DateTime]::Parse($Timestamp, [CultureInfo]::InvariantCulture).ToUniversalTime()
                Write-Debug -Message "Provided timestamp is a string: $($timestampAsDate.ToString($dateFormat))"
            } else {
                $timestampAsDate = [DateTime]::Parse('1970-01-01T00:00:00Z', [CultureInfo]::InvariantCulture).ToUniversalTime().AddSeconds($Timestamp.Substring(0, 10))
                Write-Debug -Message "Provided timestamp is a number: $($timestampAsDate.ToString($dateFormat))"
            }
        } elseif ($Date) {
            $timestampAsDate = $Date.ToUniversalTime()
            Write-Debug -Message "Provided timestamp is a date: $($Date.ToString($dateFormat))"
        } else {
            # No timestamp or date provided, generating a brand new timestamp
            $timestampAsDate = [DateTime]::UtcNow
            Write-Debug -Message "Generated new timestamp: $($timestampAsDate.ToString($dateFormat))"
        }

        # Current time as DateTimeOffset
        $now = [DateTimeOffset]::UtcNow

        # Convert to Unix epoch nanoseconds
        $out = $now.ToUnixTimeMilliseconds() * 1000000 + ($now.Ticks % 10000) * 100
        [string]$out
    }
}

Export-ModuleMember -Function Send-LokiLog