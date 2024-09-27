Install-Module DattoRMM -Force
Install-Module ITGlueAPI -Force

Import-Module DattoRMM -Force
Import-Module ITGlueAPI -Force

#Set ITGlue
Add-ITGlueBaseURI ''
Add-ITGlueAPIKey ''
Export-ITGlueModuleSettings

#Import ITGlue
Import-ITGlueModuleSettings
 
# Provide API Parameters
$params = @{
    Url        =  ''
    Key        =  ''
    SecretKey  =  ''
}
 
# Set API Parameters
Set-DrmmApiParameters @params

##############################

function Test-IPInRange {
    param (
        [string]$ipAddress,
        [string]$subnet
    )

    function ConvertTo-Int {
        param ($ip)
        $parts = $ip.Split('.')
        return [int32](([int32]$parts[0] -shl 24) -bor
                       ([int32]$parts[1] -shl 16) -bor
                       ([int32]$parts[2] -shl 8) -bor
                       ([int32]$parts[3]))
    }

    $subnetParts = $subnet.Split('/')
    $subnetAddress = $subnetParts[0]
    $prefixLength = [int]$subnetParts[1]

    $subnetInt = ConvertTo-Int $subnetAddress
    $ipInt = ConvertTo-Int $ipAddress

    $subnetMask = -bnot ([math]::Pow(2, 32 - $prefixLength) - 1)

    if (($ipInt -band $subnetMask) -eq ($subnetInt -band $subnetMask)) {
        return $true
    } else {
        return $false
    }
}

# $ITGSites = Get-ITGlueFlexibleAssets -filter_flexible_asset_type_id 2878136272142543 -filter_organization_id 2878233305809037 #BBOWT
 
#Get devices
$Sites = Get-DrmmAccountSites

$sitesNames = $sites.name
$sitesnamesCL = @()

$sitesNames | ForEach-Object {
    # Use a regular expression to extract the name part
    if ($_ -match "\(([^)]+)\)") {
        $sitesnamesCL += $matches[1] # $matches[1] contains the part inside the brackets
    }
}

$customerNamesCL = $sitesnamesCL | Select-Object -Unique

$customerNamesCL | ForEach-Object {

    $customerName = $_

    $ITGOrg = Get-ITGlueOrganizations -filter_name $customerName

    $ITGSites = Get-ITGlueFlexibleAssets -filter_flexible_asset_type_id 2878136272142543 -filter_organization_id $itgorg.data.id

    $ITGSitesLU = @{}

    $ITGSites.data | ForEach-Object {

        $subnet = $null
        $name = $null

        $subnet = $_.attributes.traits.subnet
        $name = $_.attributes.traits.location.values.name

        $ITGSitesLU[$subnet] = $name

    }

    #Site map directory
    $siteLU = @()

    foreach ($s in $sites) {
        if ($s.name -match $customerName) {
            $siteLU += $s 
        }
    }
     
    #Populate devices
    $Sites | ForEach-Object {
    
        if ($_.name -match $customerName) {

            $CurrentDevices = $null
            $CurrentDevices += Get-DrmmSiteDevices -siteUid $_.uid
        
            foreach ($device in $currentdevices) {
                
                $intIpAddress = $device.intIpAddress
                foreach ($key in $ITGSitesLU.Keys) {
                    if (Test-IPInRange -ipAddress $intIpAddress -subnet '192.168.0.0/24') {
                        Write-Host "Skipping for 192.168.0.0/24"
                    } elseif(Test-IPInRange -ipAddress $intIpAddress -subnet $key) {
                        write-host "Found device for customer" $customerName "with device name" $device.hostname "which has the subnet match of" $key "which is the site" $ITGSitesLU[$key]
                        #Write-host (($ITGSitesLU[$key]).Split('(')[0])
                        foreach ($s in $siteLU) {
                            #Write-Host ((($s.name).Split('/'))[0])
                            
                            if ($ITGSitesLU[$key] -eq $null) {
    
                            } elseif (((($s.name).Split('/'))[0]).Trim() -match (($ITGSitesLU[$key]).Split('(')[0]).Trim()) {
                                write-host "Datto Site is" $s.name
                                Move-DrmmDeviceToSite -deviceUid $device.uid -siteUid $s.uid
                            }
                        }                  
                    } else {
                        
                    }
                }
            }
        }
    }
}