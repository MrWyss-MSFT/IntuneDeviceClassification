# Intune Device Classification

<p align="center">
  <img alt="ai Intune Device Classification logo" src="_res/pictures/IDCGHLogo.png" width="400">
</p>

---

***<p style="text-align: center;">«Classifies, tags or categorize devices so that dynamic Entra ID groups can be created based on device classification.»</p>***

---

## Overview

This solution has two main components:

- **Intune Remediation Script**
- **Azure Automation Runbook**

The **Intune Remediation Script** determines the classification of a device (e.g. CAD Device) and outputs the classification to the GraphAPI. This is fully customizable and can be used to classify devices based on any criteria.

The **Azure Automation Runbook** queries the GraphAPI for devices that have been classified and stores that device classification in a custom attribute (`extensionAttribute1-15`) in Entra ID.

```mermaid
sequenceDiagram
participant Clients
participant Intune
box transparent GraphAPI
participant Intune Endpoint
participant Entra ID Endpoint
end
box transparent Azure Automation
participant Azure Runbook
end

loop Remediation Script
Intune->>Clients: remediation detection script assignment
Clients->>Clients: Runs remediation detection script, outputs device classification
Clients->>Intune: Return script output (e.g. CAD Device)
Intune->>Intune Endpoint: Stores output (preRemediationDetectionScriptOutput)
end
loop Azure Automation Runbook
    Azure Runbook->>Intune Endpoint: Query preRemediationDetectionScriptOutput
    Intune Endpoint->>Azure Runbook: Return devices with preRemediationDetectionScriptOutput
    Azure Runbook-->Azure Runbook:  processes all devices with output
    Azure Runbook->>Entra ID Endpoint: Stores preRemediationDetectionScriptOutput as ExtensionAttribute
end
```

<p align="center">
  <img alt="IntuneDeviceClassification Screenshots" src="_res/pictures/IntuneDeviceClassification.png" width="1024">
</p>

## Software Requirements

- Microsoft Visual Studio Code (`winget install vscode`)
- Polyglot Notebooks (`Ctrl+P` -> `ext install ms-dotnettools.dotnet-interactive-vscode`)
- Markdown Preview Mermaid Support (optional) (`Ctrl+P` -> `ext install bierner.markdown-mermaid`)
- .net 8.0 (`winget install Microsoft.DotNet.SDK.8`)

## Setup

1. Clone this repo
2. Open the repo in vscode
3. Create .env file in the root of the repo

    ```text
    TenantID="yourtenant.onmicrosoft.com"
    SubscriptionID="yoursubscriptionid"
    AppRegistrationName="Intune Device Classification"
    CertifcateName="Intune Device Classification Certificate"
    PubCertifcateFileName="IntuneDeviceClassificationCert.cer"
    PrivCertifcateFileName="IntuneDeviceClassificationCert.pfx"
    AutomationAccountName="aa-intunedeviceclassification"
    ResourceGroupName="rg-deviceclassification"
    Location="eastus"
    Plan="Basic"
    ClearValue="clear"
    DeviceClassificationList="CAD,Kiosk,Special Device,clear"
    ExtensionAttribute="extensionAttribute13"
    RemediationScriptName="Device Classification"
    AppConnectionName="AzureAppConnection"
    RunBookName="rb_intunedeviceclassification"
    DailyScheduleTime="23:00"
    ```

4. Open the `IntuneDeviceClassification.ipynb` notebook
5. Run the notebook (with vcode extension)

## Usage

### Intune Remediation Script

The remediation script can be customized to classify devices based on any criteria. Make sure it returns a short string (e.g. CAD Device) and exits with a 0 exit code. The string needs to be added to the `DeviceClassificationList` in the Azure Automation Variable, so that the script processes the device classification.

**ClearValue** is used to clear the classification and therefore clear the `extensionAttribute` in Entra ID. The value of `ClearValue` needs to match with `ClearValue` variable value in the Azure Automation Account. This was a design decision to prevent accidental clearing of the `extensionAttribute` in Entra ID and to limit the number of GraphAPI calls.

### Azure Automation Runbook

The Azure Automation Runbook is scheduled to run daily. It queries the GraphAPI for devices that have been classified and stores that device classification in a custom attribute (`extensionAttribute1-15`) in Entra ID.

## Some design decisions

- No client component, other than what Intune already provides (remediation script).
- No secrets on the clients
- limit the number of GraphAPI calls
- extensionAttribute in favor of Intune Category as there is only one Intune Category per device
- Works with Entra ID joined and Hybrid Entra ID joined devices
- Works with and without ConfigMgr co-management
- The Runbook is scheduled to run daily. This is to limit the number of GraphAPI calls. Increase the frequency doesn't make sense as the device classification doesn't change that often and the remediation script does not run that often.

## Other considerations

- Selecting the extensionAttribute1-15 needs to be done carefully. Check with your other teams if they are using any of the extensionAttributes.

## Costs

As of now, I don't have a good estimate of the costs. I will update this section once I have a better idea. The Azure Automation Runbook is scheduled to run daily and the runtime depends on how many devices need to be classified. See Azure Automation pricing for more details here: <https://azure.microsoft.com/en-us/pricing/details/automation/>
