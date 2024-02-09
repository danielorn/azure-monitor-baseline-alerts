targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'NetworkWatcherRG' // Note, this is the default NetworkWatcher resource group. Do not change.

@description('Optional. The location to deploy resources to.')
param location string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'nnwcom'

@description('Optional. Enable telemetry via a Globally Unique Identifier (GUID).')
param enableDefaultTelemetry bool = true

// ============ //
// Dependencies //
// ============ //

// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module nestedDependencies 'dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-nestedDependencies'
  params: {
    managedIdentityName: 'dep-<<namePrefix>>-msi-${serviceShort}'
    firstNetworkSecurityGroupName: 'dep-<<namePrefix>>-nsg-1-${serviceShort}'
    secondNetworkSecurityGroupName: 'dep-<<namePrefix>>-nsg-2-${serviceShort}'
    virtualMachineName: 'dep-<<namePrefix>>-vm-${serviceShort}'
    virtualNetworkName: 'dep-<<namePrefix>>-vnet-${serviceShort}'
    location: location
  }
}

// Diagnostics
// ===========
module diagnosticDependencies '../../../../.shared/.templates/diagnostic.dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-diagnosticDependencies'
  params: {
    storageAccountName: 'dep<<namePrefix>>diasa${serviceShort}01'
    logAnalyticsWorkspaceName: 'dep-<<namePrefix>>-law-${serviceShort}'
    eventHubNamespaceEventHubName: 'dep-<<namePrefix>>-evh-${serviceShort}'
    eventHubNamespaceName: 'dep-<<namePrefix>>-evhns-${serviceShort}'
    location: location
  }
}

// ============== //
// Test Execution //
// ============== //
#disable-next-line no-hardcoded-location // Disabled as the default RG & location are created in always one location, but each test has to deploy into a different one
var testLocation = 'westeurope'
module testDeployment '../../deploy.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-test-${serviceShort}'
  params: {
    enableDefaultTelemetry: enableDefaultTelemetry
    name: 'NetworkWatcher_${testLocation}'
    location: testLocation
    connectionMonitors: [
      {
        name: '<<namePrefix>>-${serviceShort}-cm-001'
        endpoints: [
          {
            name: '<<namePrefix>>-subnet-001(${resourceGroup.name})'
            resourceId: nestedDependencies.outputs.virtualMachineResourceId
            type: 'AzureVM'
          }
          {
            address: 'www.bing.com'
            name: 'Bing'
            type: 'ExternalAddress'
          }
        ]
        testConfigurations: [
          {
            httpConfiguration: {
              method: 'Get'
              port: 80
              preferHTTPS: false
              requestHeaders: []
              validStatusCodeRanges: [
                '200'
              ]
            }
            name: 'HTTP Bing Test'
            protocol: 'Http'
            successThreshold: {
              checksFailedPercent: 5
              roundTripTimeMs: 100
            }
            testFrequencySec: 30
          }
        ]
        testGroups: [
          {
            destinations: [
              'Bing'
            ]
            disable: false
            name: 'test-http-Bing'
            sources: [
              '<<namePrefix>>-subnet-001(${resourceGroup.name})'
            ]
            testConfigurations: [
              'HTTP Bing Test'
            ]
          }
        ]
        workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
      }
    ]
    flowLogs: [
      {
        enabled: false
        storageId: diagnosticDependencies.outputs.storageAccountResourceId
        targetResourceId: nestedDependencies.outputs.firstNetworkSecurityGroupResourceId
      }
      {
        formatVersion: 1
        name: '<<namePrefix>>-${serviceShort}-fl-001'
        retentionInDays: 8
        storageId: diagnosticDependencies.outputs.storageAccountResourceId
        targetResourceId: nestedDependencies.outputs.secondNetworkSecurityGroupResourceId
        trafficAnalyticsInterval: 10
        workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Reader'
        principalIds: [
          nestedDependencies.outputs.managedIdentityPrincipalId
        ]
        principalType: 'ServicePrincipal'
      }
    ]
    tags: {
      Environment: 'Non-Prod'
      Role: 'DeploymentValidation'
    }
  }
}
