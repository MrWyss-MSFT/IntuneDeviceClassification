$StartTime = Get-Date
$Connection = Get-AutomationConnection -Name 'AzureAppConnection'
Connect-MgGraph -ClientID $Connection.ApplicationId -TenantId $Connection.TenantId -CertificateThumbprint $Connection.CertificateThumbprint -NoWelcome

# Get Automation Variables
$RemediationScriptID = Get-AutomationVariable -Name 'RemediationScriptID'
$ExtensionAttribute = Get-AutomationVariable -Name 'ExtensionAttribute'
$ClearValue = (Get-AutomationVariable -Name 'ClearValue').trim()
$DeviceClassificationList = (Get-AutomationVariable -Name 'DeviceClassificationList') -split ',\s*' | foreach {$_.trim()}
$DeviceClassificationList += $ClearValue

#region Functions 
Function Get-MgGraphAllPages {
    [CmdletBinding(
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'SearchResult'
    )]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'NextLink', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('@odata.nextLink')]
        [string]$NextLink
        ,
        [Parameter(Mandatory = $true, ParameterSetName = 'SearchResult', ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [PSObject]$SearchResult
        ,
        [Parameter(Mandatory = $false)]
        [switch]$ToPSCustomObject
    )

    begin {}

    process {
        if ($PSCmdlet.ParameterSetName -eq 'SearchResult') {
            # Set the current page to the search result provided
            $page = $SearchResult

            # Extract the NextLink
            $currentNextLink = $page.'@odata.nextLink'

            # We know this is a wrapper object if it has an "@odata.context" property
            #if (Get-Member -InputObject $page -Name '@odata.context' -Membertype Properties) {
            # MgGraph update - MgGraph returns hashtables, and almost always includes .context
            # instead, let's check for nextlinks specifically as a hashtable key
            if ($page.ContainsKey('@odata.count')) {
                Write-Verbose "First page value count: $($Page.'@odata.count')"    
            }

            if ($page.ContainsKey('@odata.nextLink') -or $page.ContainsKey('value')) {
                $values = $page.value
            }
            else {
                # this will probably never fire anymore, but maybe.
                $values = $page
            }

            # Output the values
            # Default returned objects are hashtables, so this makes for easy pscustomobject conversion on demand
            if ($values) {
                if ($ToPSCustomObject) {
                    $values | ForEach-Object { [pscustomobject]$_ }   
                }
                else {
                    $values | Write-Output
                }
            }
        }
        $pages = 0
        while (-Not ([string]::IsNullOrWhiteSpace($currentNextLink))) {
            # Make the call to get the next page
            try {
                $page = Invoke-MgGraphRequest -Uri $currentNextLink -Method GET
            }
            catch {
                throw $_
            }

            # Extract the NextLink
            $currentNextLink = $page.'@odata.nextLink'

            # Output the items in the page
            $values = $page.value

            # increats page counter
            $pages++

            if ($page.ContainsKey('@odata.count')) {
                Write-Log -Message "Current page $($pages) value count: $($Page.'@odata.count')"
                #Write-Progress -Id 4 -PercentComplete ($($Page.'@odata.count') / $($Page.'@odata.count' * 100)) -Status "Current page value count: $($Page.'@odata.count')" -Activity "Retrieving.."
            }

            # Default returned objects are hashtables, so this makes for easy pscustomobject conversion on demand
            if ($ToPSCustomObject) {
                $values | ForEach-Object { [pscustomobject]$_ }   
            }
            else {
                $values | Write-Output
            }
        }
    }

    end {}
}
Function Set-DeviceExtensionAttribute {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline)]
        [String[]]$EntraObjectID,

        [Parameter(Position = 0, Mandatory = $True)]
        [ValidateSet('extensionAttribute1', 'extensionAttribute2', 'extensionAttribute2', 'extensionAttribute4', 'extensionAttribute5', 'extensionAttribute6', 'extensionAttribute7', 'extensionAttribute8', 'extensionAttribute9', 'extensionAttribute10', 'extensionAttribute11', 'extensionAttribute12', 'extensionAttribute13', 'extensionAttribute14', 'extensionAttribute15')]
        [String]$ExtensionAttribute,
    
        [Parameter(Mandatory = $True)]
        [AllowEmptyString()]
        [ValidateLength(0, 1024)]
        [string]$Value,

        [Parameter(Mandatory = $False)]
        [switch]$ResolveHostname
    )    
    
    Begin {
        # Check to Microsoft Graph Connection
   
        if ("Device.ReadWrite.All" -notin (Get-MgContext | Select-Object -ExpandProperty Scopes)) {
            Write-Warning "Connect to Microsoft Graph with scope Directory.ReadWrite.All first"
            exit 1
        }

        # Setup Endpoint
        $entraObjectBaseURI = "https://graph.microsoft.com/beta/devices"

        # Prepare ExtensionAtttributes json
        $ExtensionAttributes = @{}
        $ExtensionAttributes.Add("extensionAttributes", @{$ExtensionAttribute = $Value })
        $ExtensionAttributesJson = ConvertTo-Json -InputObject $ExtensionAttributes -Depth 1
    }
    
    Process {
        foreach ($ObjectID in $EntraObjectID) {
            Write-Verbose "Setting $ExtensionAttribute to $Value for $ObjectID"
            $uri = "$entraObjectBaseURI/$ObjectID"
        
            #create a psobject to return
            $result = New-Object -TypeName psobject
            $result | Add-Member -MemberType NoteProperty -Name "ObjectID" -Value $ObjectID
            $result | Add-Member -MemberType NoteProperty -Name "ExtensionAttribute" -Value $ExtensionAttribute
            $result | Add-Member -MemberType NoteProperty -Name "Value" -Value $Value
            if ($ResolveHostname.IsPresent) {
                try {
                    # Resolve the HostName
                    Invoke-MgGraphRequest -Method GET -Uri $uri | Select-Object -ExpandProperty displayName | ForEach-Object {
                        $result | Add-Member -MemberType NoteProperty -Name "HostName" -Value $_
                    }
                }
                catch {
                    $result | Add-Member -MemberType NoteProperty -Name "HostName" -Value "Failed to resolve HostName (displayName)"
                }
            }
            try {
                # Set the extensionAttribute
                Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $ExtensionAttributesJson
                $result | Add-Member -MemberType NoteProperty -Name "Success" -Value $true
            }
            catch {
                Write-Verbose "Failed to set $ExtensionAttribute to $Value for $ObjectID"
                $result | Add-Member -MemberType NoteProperty -Name "Success" -Value $false
            }
            finally {
                $result
            }
        }       
    }
    
    End {
        # Clean up
        #Disconnect-MgGraph | Out-Null
    }

}
#endregion

# Get Remediation Script Devices with Output
$RemediationScriptOutputUri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$RemediationScriptID/deviceRunStates?`$select=id,preRemediationDetectionScriptOutput"
Write-Verbose "Connecting to : $RemediationScriptOutputUri"
$Devices = Invoke-MgGraphRequest -Method Get -Uri $RemediationScriptOutputUri | Get-MgGraphAllPages 
[Array]$NotClassifiedDevices = $Devices | Where-Object preRemediationDetectionScriptOutput -eq ""
[Array]$ClassifiedDevices = $Devices | Where-Object preRemediationDetectionScriptOutput -ne ""
Write-Output "Devices (Remediation Script): Total: $($Devices.count), Not Classified: $($NotClassifiedDevices.count), Classified: $($ClassifiedDevices.count)"

# Loop all DeviceClassificationList
ForEach ($DeviceClass in $DeviceClassificationList) {
    [Array]$DeviceClassFilteredDevices = $Devices | Where-Object preRemediationDetectionScriptOutput -eq $DeviceClass
    Write-Output "Processing Class: $DeviceClass (Total: $($DeviceClassFilteredDevices.count))"
    if ($DeviceClassFilteredDevices.count -ne 0) {
        Write-Output "Nr,IntuneDeviceName,EntraDeviceName,DeviceClass,ExtensionAttribute,CurrentExtensionsAttributeValue,NewExtensionAttributeValue,Status,EntraDeviceid,IntuneId"
    }
    if ($DeviceClassFilteredDevices.count -eq 0) {
        Write-Output "No devices to process"
    }
    
    # Loop all devices in the DeviceClassFilteredDevices
    ForEach ($Device in $DeviceClassFilteredDevices) {
        # Get DeviceClass index
        $i = $DeviceClassFilteredDevices.IndexOf($Device) + 1
        
        # Get Intune DeviceID
        $IntuneId = ("$($Device.id)" -split ":")[1]
        Write-Verbose " Intune ID: $IntuneId"
    
        # Get EntraID and Device Name with Intune Device ID
        $IntuneMangedDevicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($IntuneId)?`$select=azureADDeviceId,deviceName"
        Write-Verbose " Connecting to: $IntuneMangedDevicesUri"
        $IntuneDevice = Invoke-MgGraphRequest -Method Get -Uri $IntuneMangedDevicesUri
        $EntraID = $IntuneDevice.azureADDeviceId
        Write-Verbose " Entra Device ID: $EntraID"
        $IntuneDeviceName = $IntuneDevice.deviceName
        Write-Verbose " DeviceName: $IntuneDeviceName"
    
        # Get extensionAttributes
        $EntraDeviceUri = "https://graph.microsoft.com/v1.0/devices/deviceid_$($EntraID)?`$select=id,displayName,extensionAttributes"
        Write-Verbose " Connecting to: $EntraDeviceUri"
        $EntraDevice = Invoke-MgGraphRequest -Method Get -Uri $EntraDeviceUri
        $EntraDeviceName = $EntraDevice.displayName
        Write-Verbose " Entra DeviceName: $EntraDeviceName"
        $EntraDeviceid = $EntraDevice.id 
        Write-Verbose " Entra Object ID: $EntraDeviceid"
        $EntraDeviceExtensionsAttributes = $EntraDevice.extensionAttributes
        $CurrentExtensionsAttributeValue = $EntraDeviceExtensionsAttributes.$ExtensionAttribute
        Write-Verbose " Checking extensionAttributes"
        Write-Verbose "  Current Entra $($ExtensionAttribute): '$($CurrentExtensionsAttributeValue)'"
    
        # If remediation script return value is $ClearValue, clear the extensionAttribute, if not set or not equal to $DeviceClass, set the extensionAttribute value of the $DeviceClass
        $NewExtensionAttributeValue = ""
        If ($CurrentExtensionsAttributeValue -eq $ClearValue) {
            Write-Verbose "  Clearing Entra $($ExtensionAttribute)"
            $DeviceExtensionAttributeResult = Set-DeviceExtensionAttribute -EntraObjectID $EntraDeviceid -ExtensionAttribute $ExtensionAttribute -Value $NewExtensionAttributeValue
            if ($DeviceExtensionAttributeResult.Success -eq $true) {$Status = "Success"} else {$Status = "Failed"}
            Write-Verbose "  Surcess: $($DeviceExtensionAttributeResult.Success)"
        }
        else {
            If ($CurrentExtensionsAttributeValue -ne $DeviceClass) {
                $NewExtensionAttributeValue = $DeviceClass
                Write-Verbose "  Setting Entra $($ExtensionAttribute): '$($NewExtensionAttributeValue)'"
                $DeviceExtensionAttributeResult = Set-DeviceExtensionAttribute -EntraObjectID $EntraDeviceid -ExtensionAttribute $ExtensionAttribute -Value $NewExtensionAttributeValue
                if ($DeviceExtensionAttributeResult.Success -eq $true) {$Status = "Success"} else {$Status = "Failed"}
                Write-Verbose "  Success: $($DeviceExtensionAttributeResult.Success)"
            }
            else {
                Write-Verbose "  Entra $($ExtensionAttribute) already set to: '$($NewExtensionAttributeValue)'"
                $NewExtensionAttributeValue = $DeviceClass
                $Status = "Already Set"
            }
        }
        # Log output
        $LogOutput = "$($i),$($IntuneDeviceName),$($EntraDeviceName),$($DeviceClass),$($ExtensionAttribute),$($CurrentExtensionsAttributeValue),$($NewExtensionAttributeValue),$($Status),$($EntraDeviceid),$($IntuneId)"
        Write-Output $LogOutput
    }
}
$EndTime = Get-Date
$ElapsedTime = [Math]::Round(($EndTime - $StartTime).TotalSeconds, 1)
Write-Output "Script Duration: $elapsedTime seconds"