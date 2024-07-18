# Prompt the user for input and store the values in variables
$apiKey = Read-Host "Please enter your API Key"
$clientURL = Read-Host "Please enter the Client URL"

$HuduURL = $clientURL -replace '/c/.*', '' 
$URLslug = $clientURL -replace '.*c/', ''

$baseURL = "$HuduURL/api/v1"

function Get-ClientId {
    # Define the API endpoint with the encoded client name
    $endpoint = "$baseURL/companies?slug=$URLslug"
    try {
        # Perform the GET request using the correct header for API key
        $response = Invoke-RestMethod -Uri $endpoint -Method Get -Headers @{ "x-api-key" = $apiKey }

        # Extract the ID from the first company in the response array
        if ($response.companies -and $response.companies.Count -gt 0) {
            return $response.companies[0].id
        } else {
            Write-Output "No company was found"
            return $null
        }
    } catch {
        Write-Host "Error: $_"
        return $null
    }
}

function Get-Hostname {
    return $env:computername

}

function Get-Brand {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -Property Manufacturer
    return $computerSystem.Manufacturer
}

function Get-Model {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -Property Model
    return $computerSystem.Model
}

function Get-PrimaryEthernetAdapter {
    $activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.PhysicalMediaType -ne 'Native 802.11' }
    foreach ($adapter in $activeAdapters) {
        $ipAddressDetails = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex | Where-Object { $_.AddressFamily -eq 'IPv4' }
        foreach ($ip in $ipAddressDetails) {
            if ($ip.PrefixOrigin -eq 'Dhcp' -or $ip.PrefixOrigin -eq 'Manual') {
                return $adapter
            }
        }
    }
    return $null
}

function Get-WiFiAdapter {
    $wifiAdapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' }
    foreach ($adapter in $wifiAdapters) {
        return $adapter
    }
    return $null
}

function Get-IPAddressWiFi {
    $primaryAdapter = Get-WiFiAdapter
    if ($primaryAdapter) {
        # Check if the adapter is connected
        $adapterStatus = Get-NetAdapter -Name $primaryAdapter.Name | Where-Object { $_.Status -eq 'Up' }
        if ($adapterStatus) {
            $ipAddressDetails = Get-NetIPAddress -InterfaceIndex $primaryAdapter.ifIndex | Where-Object { $_.AddressFamily -eq 'IPv4' }
            if ($ipAddressDetails) {
                $ipAddress = ($ipAddressDetails | Where-Object { $_.InterfaceIndex -eq $primaryAdapter.ifIndex }).IPAddress -join ', '
                return $ipAddress
            } else {
                return ""
            }
        } else {
            return ""
        }
    } else {
        return ""
    }
}

function Get-MACAddressWiFi {
    $primaryAdapter = Get-WiFiAdapter
    if ($primaryAdapter) {
        return $primaryAdapter.MacAddress -replace '-', ':'
    } else {
        return ""
    }
}

function Get-IPAddressEthernet {
    $wifiAdapter = Get-WiFiAdapter
    if ($wifiAdapter) {
        $wifiStatus = Get-NetAdapter -Name $wifiAdapter.Name | Where-Object { $_.Status -eq 'Up' }
        if ($wifiStatus) {
            return ""
        }
    }

    $primaryAdapter = Get-PrimaryEthernetAdapter
    if ($primaryAdapter) {
        $ipAddressDetails = Get-NetIPAddress -InterfaceIndex $primaryAdapter.ifIndex | Where-Object { $_.AddressFamily -eq 'IPv4' }
        if ($ipAddressDetails) {
            return ($ipAddressDetails | Where-Object { $_.InterfaceIndex -eq $primaryAdapter.ifIndex }).IPAddress -join ', '
        } else {
            Write-Host "No IP address found for Ethernet adapter."
            
        }
    } else {
        Write-Host "No primary Ethernet adapter found."
        
    }
}

function Get-MACAddressEthernet {
    $primaryAdapter = Get-PrimaryEthernetAdapter
    if ($primaryAdapter) {
        return $primaryAdapter.MacAddress -replace '-', ':'
    } else {
        Write-Host "No primary adapter found."
        
    }
}

function Get-CPU {
    $processor = Get-CimInstance -ClassName Win32_Processor
    return $processor.Name
}

function Get-Memory {
    $totalMemoryGB = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB
    return "{0:N2} GB" -f $totalMemoryGB
}

function Get-Drive {
    # Get all physical disks
    $disks = Get-PhysicalDisk

    # Determine the largest disk based on size
    $largestDisk = $disks | Sort-Object -Property Size -Descending | Select-Object -First 1

    # Determine the media type (SSD, HDD, or NVMe)
    $mediaType = switch ($largestDisk.MediaType) {
        "SSD" { "SSD" }
        "HDD" { "HDD" }
        "Unspecified" { if ($largestDisk.BusType -eq "NVMe") { "NVMe SSD" } else { $largestDisk.MediaType } }
        default { $largestDisk.MediaType }
    }

    # Return the size in GB and the media type
    $sizeGB = [math]::Round($largestDisk.Size / 1GB, 2)
    return "$sizeGB GB $mediaType"
}

function Get-OperatingSystem {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -Property Caption
    $formattedOsName = $osInfo.Caption -replace 'Microsoft Windows', 'Windows' -replace '64-bit', ''
    return "$formattedOsName"
}

function Get-Notes {
    $notes = Read-Host "Enter any notes"
    return "$notes"
}

function Send-PCInfoToHudu {
    $assetTypeId = 9  # Asset type ID for Windows PCs
    $clientID = Get-ClientId
    
    # Endpoint to create an asset in Hudu
    $endpoint = "$baseURL/companies/$clientID/assets"
 
    # Headers for the API request
    $headers = @{
        "x-api-key" = "$apiKey"
    }

    # Body of the request
    $body = @{
        asset = @{
            asset_layout_id = $assetTypeId
            name = $($pcInfo.Hostname)
            fields = @(
                @{
                    value = $($pcInfo.Hostname)
                    asset_layout_field_id = 81  # Hostname
                },
                @{
                    value = $($pcInfo.Brand)
                    asset_layout_field_id = 56  #  Brand
                },
                @{
                    value = $($pcInfo.Model)
                    asset_layout_field_id = 57  # Model
                },
                @{
                    value = $($pcInfo.IPAddressEthernet)
                    asset_layout_field_id = 173  #  IP Address (Ethernet)
                }
                @{
                    value = $($pcInfo.MACAddressEthernet)
                    asset_layout_field_id = 171  # MAC Address (Ethernet)
                },
                @{
                    value = $($pcInfo.IPAddressWiFi)
                    asset_layout_field_id = 174  # IP Address (Wi-Fi)
                },
                @{
                    value = $($pcInfo.MACAddressWiFi)
                    asset_layout_field_id = 172  # MAC Address (Wi-Fi)
                },
                @{
                    value = $($pcInfo.CPU)
                    asset_layout_field_id = 140  # CPU
                },
                @{
                    value = $($pcInfo.Memory)
                    asset_layout_field_id = 58  # Memory
                },
                @{
                    value = $($pcInfo.Drive)
                    asset_layout_field_id = 59  # Drive
                },
                @{
                    value = $($pcInfo.OperatingSystem)
                    asset_layout_field_id = 62  # Operating system
                },
                @{
                    value = $($pcInfo.Notes)
                    asset_layout_field_id = 63  # Notes
                }
            )
        }
    } | ConvertTo-Json -Depth 5

    try {
        # Perform the POST request
        write-host "Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{ "x-api-key" = "U2a812rA9EKwQL6gxZCU1MVZ"} -Body $body -ContentType "application/json""
        $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{ "x-api-key" = "U2a812rA9EKwQL6gxZCU1MVZ"} -Body $body -ContentType "application/json"
        Write-Output "Asset successfully created with ID: $($response.id)"
    } catch {
        Write-Output "Failed to create asset in Hudu: $_"
    }
}

# Create a PowerShell object with the properties
$pcInfo = [PSCustomObject]@{
    Hostname = Get-Hostname
    Brand = Get-Brand
    Model = Get-Model
    IPAddressEthernet = Get-IPAddressEthernet
    MACAddressEthernet = Get-MACAddressEthernet
    IPAddressWiFi = Get-IPAddressWiFi
    MACAddressWiFi = Get-MACAddressWiFi
    CPU = Get-CPU
    Memory = Get-Memory
    Drive = Get-Drive
    Location = ""
    OperatingSystem = Get-OperatingSystem
    Notes = Get-Notes
}

# Convert the object to JSON
$json = $pcInfo | ConvertTo-Json

# Output the JSON
Write-Output $json
Send-PCInfoToHudu
