targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('Name of the resource group the search service and deployed embedding model are in')
param resourceGroupName string  = ''// Set in main.parameters.json

@allowed([ 'free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2' ])
param searchServiceSkuName string // Set in main.parameters.json

@description('Display name of Computer Vision API account')
param computerVisionAccountName string = '' // Set in main.parameters.json

param useGPT4V bool = false // Set in main.parameters.json

@description('SKU for Computer Vision API')
@allowed([
  'F0'
  'S1'
])
param computerVisionSkuName string // Set in main.parameters.json

param computerVisionLocation string = '' // Set in main.parameters.json

param computerVisionResourceGroupName string = '' // Set in main.parameters.json

param searchServiceLocation string = '' // set in main.parameters.json

param searchServiceName string = '' // Set in main.parameters.json

param searchServiceResourceGroupName string = ''// Set in main.parameters.json

param semanticSearchSkuName string = '' // Set in main.parameters.json

param storageLocation string = '' // Set in main.parameters.json

param storageResourceGroupName string = '' // Set in main.parameters.json

param storageAccountName string = '' // Set in main.parameters.json

param appServicePlanName string = '' // Set in main.parameters.json

param apiServiceName string = '' // Set in main.parameters.json

param apiServiceLocation string = '' // Set in main.parameters.json

param apiServiceResourceGroupName string = '' // Set in main.parameters.json

param frontendServiceName string = '' // Set in main.parameters.json

param logAnalyticsName string = '' // Set in main.parameters.json

param applicationInsightsName string = '' // Set in main.parameters.json

param searchIndexName string = '' // Set in main.parameters.json

param frontendAppServicePlanName string = '' // Set in main.parameters.json

param frontendAppServicePlanSkuName string = '' // Set in main.parameters.json

param chatGpt4vDeploymentCapacity int = 10 // Set in main.parameters.json
param gpt4vModelName string = 'gpt-4' // Set in main.parameters.json
param gpt4vDeploymentName string = 'gpt-4v' // Set in main.parameters.json
param gpt4vModelVersion string = 'vision-preview' // Set in main.parameters.json
// https://learn.microsoft.com/en-us/azure/ai-services/openai/gpt-v-quickstart
@description('Location for the OpenAI resource group')
@allowed(['switzerlandnorth', 'westus', 'australiaeast', 'swedencentral'])
@metadata({
  azd: {
    type: 'location'
  }
})
param openAiResourceGroupLocation string // Set in main.parameters.json
param openAiServiceName string = '' // Set in main.parameters.json
param openAiResourceGroupName string = '' // Set in main.parameters.json

param openAiSkuName string = 'S0'

// Cannot use semantic search on free tier
var actualSemanticSearchSkuName = searchServiceSkuName == 'free' ? 'disabled' : semanticSearchSkuName

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: empty(resourceGroupName) ? '${abbrs.resourcesResourceGroups}${environmentName}' : resourceGroupName
  location: location
  tags: tags
}

resource searchServiceResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' existing = if (!empty(searchServiceResourceGroupName)) {
  name: !empty(searchServiceResourceGroupName) ? searchServiceResourceGroupName : resourceGroup.name
}

resource apiServiceResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' existing = if (!empty(apiServiceResourceGroupName)) {
  name: !empty(apiServiceResourceGroupName) ? apiServiceResourceGroupName : resourceGroup.name
}

resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' existing = if (!empty(storageResourceGroupName)) {
  name: !empty(storageResourceGroupName) ? storageResourceGroupName : resourceGroup.name
}

resource computerVisionResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' existing = if (!empty(computerVisionResourceGroupName)) {
  name: !empty(computerVisionResourceGroupName) ? computerVisionResourceGroupName : resourceGroup.name
}

resource openAiResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(openAiResourceGroupName)) {
  name: !empty(openAiResourceGroupName) ? openAiResourceGroupName : resourceGroup.name
}

module searchService 'core/search/search-services.bicep' = {
  name: 'search-service'
  scope: searchServiceResourceGroup
  params: {
    name: empty(searchServiceName) ? '${abbrs.searchSearchServices}${resourceToken}' : searchServiceName
    location: empty(searchServiceLocation) ? location : searchServiceLocation
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'  
      }
    }
    sku: {
      name: searchServiceSkuName
    }
    semanticSearch: actualSemanticSearchSkuName
    tags: tags
  }
}

// Create an App Service Plan for the backend
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: apiServiceResourceGroup
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: empty(apiServiceLocation) ? location : apiServiceLocation
    tags: tags
    sku: {
      name: 'Y1'
      tier: 'Dynamic'
    }
  }
}

// Backing storage for Azure functions backend API and sample data
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: storageResourceGroup
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: empty(storageLocation) ? location : storageLocation
    tags: tags
    allowBlobPublicAccess: true
  }
}

// Storage contributor role to upload sample data
module storageContribRoleUser 'core/security/role.bicep' = {
  scope: storageResourceGroup
  name: 'storage-contribrole-user'
  params: {
    principalId: principalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalType: 'User'
  }
}

// Cognitive Services user to use gpt4v

module openAiRoleUser 'core/security/role.bicep' = if (useGPT4V) {
  scope: openAiResourceGroup
  name: 'openai-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'User'
  }
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: apiServiceResourceGroup
  params: {
    location: empty(apiServiceLocation) ? location : apiServiceLocation
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
  }
}

// Computer vision account for vision embeddings
module computerVision 'core/ai/cognitiveservices.bicep' = {
  name: 'computervision'
  scope: computerVisionResourceGroup
  params: {
    name: !empty(computerVisionAccountName) ? computerVisionAccountName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: empty(computerVisionLocation) ? location : computerVisionLocation
    kind: 'ComputerVision'
    sku: {
      name: computerVisionSkuName
    }
  }
}

// The custom skill
module functionApp 'core/host/functions.bicep' = {
  name: 'function'
  scope: apiServiceResourceGroup
  params: {
    name: !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
    location: !empty(apiServiceLocation) ? apiServiceLocation : location
    tags: union(tags, { 'azd-service-name': 'api' })
    alwaysOn: false
    appSettings: {
      AzureWebJobsFeatureFlags: 'EnableWorkerIndexing'
      COGNITIVE_SERVICES_ENDPOINT: computerVision.outputs.endpoint
      // TODO: Setup keyvault. Outputting key into env var for ease of use is not ideal
      COGNITIVE_SERVICES_API_KEY: computerVision.outputs.key
    }
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'python'
    runtimeVersion: '3.10'
    storageAccountName: storage.outputs.name
  }
}

// Create an App Service Plan for the frontend
module frontendAppServicePlan './core/host/appserviceplan.bicep' = {
  name: 'frontendappserviceplan'
  scope: apiServiceResourceGroup
  params: {
    name: !empty(frontendAppServicePlanName) ? frontendAppServicePlanName : '${abbrs.webServerFarms}frontend-${resourceToken}'
    location: empty(apiServiceLocation) ? location : apiServiceLocation
    tags: tags
    sku: {
      name: frontendAppServicePlanSkuName
    }
  }
}

// The application frontend
module frontend 'core/host/appservice.bicep' = {
  name: 'web'
  scope: apiServiceResourceGroup
  params: {
    name: !empty(frontendServiceName) ? frontendServiceName : '${abbrs.webSitesAppService}frontend-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'frontend' })
    appServicePlanId: frontendAppServicePlan.outputs.id
    runtimeName: 'python'
    runtimeVersion: '3.11'
    appCommandLine: 'python3 -m gunicorn main:app'
    scmDoBuildDuringDeployment: true
    managedIdentity: true
    appSettings: {
      AZURE_SEARCH_INDEX: searchIndexName
      AZURE_SEARCH_SERVICE: searchService.outputs.name
    }
  }
}

// Frontend reader role to query index data
module frontendReaderRoleUser 'core/security/role.bicep' = {
  scope: searchServiceResourceGroup
  name: 'frontend-readrole-user'
  params: {
    principalId: frontend.outputs.identityPrincipalId
    roleDefinitionId: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
    principalType: 'ServicePrincipal'
  }
}

// Optional GPT4V deployment on Azure for notebook deployments
module openAi 'core/ai/cognitiveservices.bicep' = if (useGPT4V) {
  name: 'openai'
  scope: openAiResourceGroup
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: openAiResourceGroupLocation
    tags: tags
    sku: {
      name: openAiSkuName
    }
    kind: 'OpenAI'
    deployments: [
      {
        name: gpt4vDeploymentName
        model: {
          format: 'OpenAI'
          name: gpt4vModelName
          version: gpt4vModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: chatGpt4vDeploymentCapacity
        }
      }
    ]
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_SEARCH_SERVICE string = searchService.outputs.name
output AZURE_SEARCH_SERVICE_RESOURCE_GROUP string = searchServiceResourceGroup.name
output AZURE_SEARCH_SERVICE_LOCATION string = searchService.outputs.location
output AZURE_SEARCH_SERVICE_SKU string = searchService.outputs.sku
output AZURE_SEARCH_INDEX string = searchIndexName

output AZURE_STORAGE_ACCOUNT_ID string = storage.outputs.id
output AZURE_STORAGE_ACCOUNT_LOCATION string = storage.outputs.location
output AZURE_STORAGE_ACCOUNT_RESOURCE_GROUP string = storageResourceGroup.name
output AZURE_STORAGE_ACCOUNT string = storage.outputs.name
output AZURE_STORAGE_ACCOUNT_BLOB_URL string = storage.outputs.primaryBlobEndpoint
output AZURE_APP_SERVICE_PLAN string = appServicePlan.outputs.name
output AZURE_API_SERVICE string = functionApp.outputs.name
output AZURE_API_SERVICE_LOCATION string = functionApp.outputs.location
output AZURE_API_SERVICE_RESOURCE_GROUP string = apiServiceResourceGroup.name
output AZURE_LOG_ANALYTICS string = monitoring.outputs.logAnalyticsWorkspaceName
output AZURE_APPINSIGHTS string = monitoring.outputs.applicationInsightsName

output AZURE_COMPUTERVISION_ACCOUNT_URL string = computerVision.outputs.endpoint

output AZURE_FUNCTION_URL string = functionApp.outputs.uri

// Specific to Azure OpenAI
output AZURE_OPENAI_SERVICE string = (useGPT4V) ? openAi.outputs.name : ''
output AZURE_OPENAI_RESOURCE_GROUP string = (useGPT4V) ? openAiResourceGroup.name : ''
output AZURE_OPENAI_GPT4V_DEPLOYMENT string = (useGPT4V) ? gpt4vDeploymentName : ''
