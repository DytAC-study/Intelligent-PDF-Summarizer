targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment, used to generate a unique hash for resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed([
  'australiaeast'
  'eastasia'
  'eastus'
  'eastus2'
  'northeurope'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'uksouth'
  'westus2'
  'eastus2euap'
  'canadacentral'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@allowed([
  'S1'        // Consumption plan SKU
])
@description('SKU name for the Function App (Consumption plan)')
param functionSkuName string = 'S1'

@allowed([
  'Standard'   // Consumption plan tier
])
@description('SKU tier for the Function App (Consumption plan)')
param functionSkuTier string = 'Standard'

param functionReservedPlan bool = true // Linux plan

@description('SKU name for Form Recognizer')
param documentIntelligenceSkuName string

@description('Name for the Form Recognizer resource')
param documentIntelligenceServiceName string = ''

param durableFunctionServiceName string = ''
param durableFunctionUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
param vNetName string = ''
param disableLocalAuth bool = true
param principalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
}
var functionAppName = !empty(durableFunctionServiceName)
  ? durableFunctionServiceName
  : '${abbrs.webSitesFunctions}${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName)
    ? resourceGroupName
    : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User-assigned identity for Durable Functions
module durableFunctionUserAssignedIdentity './core/identity/userAssignedIdentity.bicep' = {
  name: 'DurableFunctionUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    identityName: !empty(durableFunctionUserAssignedIdentityName)
      ? durableFunctionUserAssignedIdentityName
      : '${abbrs.managedIdentityUserAssignedIdentities}durable-function-${resourceToken}'
  }
}

// App Service Plan (Consumption)
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName)
      ? appServicePlanName
      : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: functionSkuName
      tier: functionSkuTier
    }
    reserved: functionReservedPlan
  }
}

// Durable Function App
module durableFunction './app/durable-function.bicep' = {
  name: 'function-app'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'python'
    runtimeVersion: '3.9'
    azureOpenaiChatgptDeployment: ''
    azureOpenaiService: ''
    storageAccountName: storage.outputs.name
    identityId: durableFunctionUserAssignedIdentity.outputs.identityId
    identityClientId: durableFunctionUserAssignedIdentity.outputs.identityClientId
    documentIntelligenceEndpoint: documentIntelligence.outputs.endpoint
    appSettings: {}
    virtualNetworkSubnetId: serviceVirtualNetwork.outputs.appSubnetID
  }
}

// Storage Account + containers
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName)
      ? storageAccountName
      : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    containers: [
      {
        name: deploymentStorageContainerName
        publicAccess: 'Blob'
      }
      {
        name: 'input'
        publicAccess: 'Blob'
      }
      {
        name: 'output'
        publicAccess: 'Blob'
      }
    ]
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: true
  }
}

// Role assignment: Durable Function identity → Storage Blob Data Owner
var storageRoleDefinitionId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
module storageRoleAssignmentApiUAMI 'app/storage-Access.bicep' = {
  name: 'storageRoleAssignmentProcessorUAMI'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageRoleDefinitionId
    principalID: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module storageRoleAssignmentApi 'app/storage-Access.bicep' = {
  name: 'storageRoleAssignmentLoginIdentity'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageRoleDefinitionId
    principalID: principalId
    principalType: 'User'
  }
}

// Virtual network
module serviceVirtualNetwork 'app/vnet.bicep' = {
  name: 'serviceVirtualNetwork'
  scope: rg
  params: {
    location: location
    tags: tags
    vNetName: !empty(vNetName)
      ? vNetName
      : '${abbrs.networkVirtualNetworks}${resourceToken}'
  }
}

module storagePrivateEndpoint 'app/storage-PrivateEndpoint.bicep' = {
  name: 'servicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName)
      ? vNetName
      : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: serviceVirtualNetwork.outputs.peSubnetName
    resourceName: storage.outputs.name
  }
}

// Monitoring (Log Analytics + Application Insights)
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName)
      ? logAnalyticsName
      : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName)
      ? applicationInsightsName
      : '${abbrs.insightsComponents}${resourceToken}'
    disableLocalAuth: disableLocalAuth
  }
}

var monitoringRoleDefinitionId = '3913510d-42f4-4e42-8a64-420c390055eb'
module appInsightsRoleAssignmentApi './core/monitor/appinsights-access.bicep' = {
  name: 'appInsightsRoleAssignmentDurableFunction'
  scope: rg
  params: {
    appInsightsName: monitoring.outputs.applicationInsightsName
    roleDefinitionID: monitoringRoleDefinitionId
    principalID: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
  }
}

// Form Recognizer (Document Intelligence)
module documentIntelligence 'br/public:avm/res/cognitive-services/account:0.5.4' = {
  name: 'documentintelligence'
  scope: rg
  params: {
    name: !empty(documentIntelligenceServiceName)
      ? documentIntelligenceServiceName
      : '${abbrs.cognitiveServicesDocumentIntelligence}${resourceToken}'
    kind: 'FormRecognizer'
    customSubDomainName: !empty(documentIntelligenceServiceName)
      ? documentIntelligenceServiceName
      : '${abbrs.cognitiveServicesDocumentIntelligence}${resourceToken}'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    location: location
    disableLocalAuth: true
    tags: tags
    sku: documentIntelligenceSkuName
  }
}

module documentIntelligenceRoleBackend 'app/documentintelligence-Access.bicep' = {
  name: 'documentintelligence-role-backend'
  scope: rg
  params: {
    principalId: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_DURABLE_FUNCTION_NAME string = durableFunction.outputs.SERVICE_DURABLE_FUNCTION_NAME
output AZURE_FUNCTION_NAME string = durableFunction.outputs.SERVICE_DURABLE_FUNCTION_NAME
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_CONTAINER_NAME string = deploymentStorageContainerName
