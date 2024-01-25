# Checks if the device needs to be tagged and classified as a special device.


# Check Functions
Function Test-RegistryValue {
    param(
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [System.Array]
        $RegistrySettingsToValidate
    )
    # Description: This script checks if the registry keys defined are set correctly.
     
    #region helper functions, enums and maps
    $RegTypeMap = @{
        REG_DWORD     = [Microsoft.Win32.RegistryValueKind]::DWord
        REG_SZ        = [Microsoft.Win32.RegistryValueKind]::String
        REG_QWORD     = [Microsoft.Win32.RegistryValueKind]::QWord
        REG_BINARY    = [Microsoft.Win32.RegistryValueKind]::Binary
        REG_MULTI_SZ  = [Microsoft.Win32.RegistryValueKind]::MultiString
        REG_EXPAND_SZ = [Microsoft.Win32.RegistryValueKind]::ExpandString
    }
    [Flags()] enum RegKeyError {
        None = 0
        Path = 1
        Name = 2
        Type = 4
        Value = 8
    }
    #endregion
    
    #region Check if registry keys are set correctly
    $KeyErrors = @()
    $Output = ""
    Foreach ($reg in $RegistrySettingsToValidate) {
        [RegKeyError]$CurrentKeyError = 15
    
        $DesiredPath = "$($reg.Hive)$($reg.Key)"
        $DesiredName = $reg.Name
        $DesiredType = $RegTypeMap[$reg.Type]
        $DesiredValue = $reg.Value
    
        # Check if the registry key path exists
        If (Test-Path -Path $DesiredPath) {
            $CurrentKeyError -= [RegKeyError]::Path
    
            # Check if the registry value exists
            If (Get-ItemProperty -Path $DesiredPath -Name $DesiredName -ErrorAction SilentlyContinue) {
                $CurrentKeyError -= [RegKeyError]::Name
    
                # Check if the registry value type is correct
                If ($(Get-Item -Path $DesiredPath).GetValueKind($DesiredName) -eq $DesiredType) {
                    $CurrentKeyError -= [RegKeyError]::Type
                    
                    # Check if the registry value is correct
                    If ($((Get-ItemProperty -Path $DesiredPath -Name $DesiredName).$DesiredName) -eq $DesiredValue) {
                        $CurrentKeyError -= [RegKeyError]::Value
                        # Write-Host "[$DesiredPath | $DesiredName | $RetTypeRegistry | $DesiredValue] exists and is correct"
                    } 
                }
            }
        }
        $KeyErrors += $CurrentKeyError
        $Output += " | $DesiredName ErrorCode = $CurrentKeyError"
    }
    #endregion
    
    #region Check if all registry keys are correct
    if (($KeyErrors.value__ | Measure-Object -Sum).Sum -eq 0) {
        return $true
    }
    else {
        return $false
    }
    #endregion
    
}

# Default Empty Output, reduces the amount of categories and therefore a faster runbook run
$Output = ""

#region CAD Device 
# Check if the CAD Device registry keys are set
# If they are set, the device is classified as a CAD Device
$CADDeviceRegistryKeys = @(
    [pscustomobject]@{
        Hive  = 'HKLM:\'
        Key   = 'SOFTWARE\YourCompany\Testing'
        Name  = 'Test2'
        Type  = 'REG_DWORD'
        Value = 1
    },
    [pscustomobject]@{
        Hive  = 'HKLM:\'
        Key   = 'SOFTWARE\YourCompany\Testing'
        Name  = 'Test'
        Type  = 'REG_SZ'
        Value = "CAD"
    }
)


# Check if the CAD Device registry keys are set
if (Test-RegistryValue -RegistrySettingsToValidate $CADDeviceRegistryKeys) {
    $Output = "CAD"
}
#endregion

#region Kiosk Device
# Check if the Kiosk Device registry keys are set
# If they are set, the device is classified as a Kiosk Device
$KioskDeviceRegistryKeys = @(

    [pscustomobject]@{
        Hive  = 'HKLM:\'
        Key   = 'SOFTWARE\YourCompany\Testing'
        Name  = 'Test'
        Type  = 'REG_SZ'
        Value = "Kiosk"
    }
)

# Check if the Kiosk Device registry keys are set
if (Test-RegistryValue -RegistrySettingsToValidate $KioskDeviceRegistryKeys) {
    $Output = "Kiosk"
}
#endregion



Write-Output $Output
exit 0
