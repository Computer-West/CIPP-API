function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        [string]$IP
    )

    $CacheGeoIPTable = Get-CippTable -tablename 'cachegeoip'
    $30DaysAgo = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "PartitionKey eq 'IP' and RowKey eq '$IP' and Timestamp ge datetime'$30DaysAgo'"
    $GeoIP = Get-CippAzDataTableEntity @CacheGeoIPTable -Filter $Filter
    if ($GeoIP -and $GeoIP.Data) {
        return ($GeoIP.Data | ConvertFrom-Json)
    }
    $EncodedIP = [System.Uri]::EscapeDataString($IP)
    $IsIPv6 = $false
    try {
        $ParsedIPAddress = [System.Net.IPAddress]::Parse($IP)
        $IsIPv6 = $ParsedIPAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6
    } catch {
        $IsIPv6 = $false
    }

    if ($IsIPv6) {
        $CountryLocation = Invoke-CIPPRestMethod -Uri "https://api.country.is/$EncodedIP"
        if ([string]::IsNullOrWhiteSpace($CountryLocation.country)) {
            Write-logMessage -API GeoIPLocation -message "Failed to get IPv6 location for $IP. api.country.is returned no country." -sev Warning
            throw "Could not get location for $IP"
        }

        $Location = [pscustomobject]@{
            ip              = $CountryLocation.ip ?? $IP
            country         = $CountryLocation.country
            countryCode     = $CountryLocation.country
            CountryOrRegion = $CountryLocation.country
        }
    } else {
        $Location = Invoke-CIPPRestMethod -Uri "https://geoipdb.azurewebsites.net/api/GetIPInfo?IP=$EncodedIP"
        if ($Location.status -eq 'FAIL') {
            Write-logMessage -API GeoIPLocation -message "Failed to get location for $IP. API returned status 'FAIL' with message: $($Location.message)" -sev Warning
            throw "Could not get location for $IP"
        }
    }
    $CacheGeo = @{
        PartitionKey = 'IP'
        RowKey       = $IP
        Data         = [string]($Location | ConvertTo-Json -Compress)
    }
    Add-AzDataTableEntity @CacheGeoIPTable -Entity $CacheGeo -Force
    return $Location
}
