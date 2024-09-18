import { getRoleDefinitions } from './role-definitions.bicep'
import { getBuiltInSqlRole } from './role-definitions.bicep'

param location string = resourceGroup().location
param tags object
param serviceName string
param env string
param uniqueId string
param groupId string

// Cosmos DB

@minLength(3)
@maxLength(44)
@description('Azure Cosmos DB account name.')
param databaseAccountName string = toLower('cosmos-${serviceName}-${uniqueId}-${env}')

resource database_account 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: databaseAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
    disableKeyBasedMetadataWriteAccess: true
    enableAutomaticFailover: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        failoverPriority: 0
        locationName: location
        isZoneRedundant: false
      }
    ]
  }
}

@description('NoSQL API database')
resource nosql_database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: database_account
  name: 'SharedDatabase'
  tags: tags
  properties: {
    resource: {
      id: 'SharedDatabase'
    }
  }
}

var containers = [
  {
    ContainerId: 'messages'
    PartionKey: 'messageType'
  }
]

@description('Database containers')
resource database_containers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = [
  for container in containers: {
    parent: nosql_database
    name: container.ContainerId
    tags: tags
    properties: {
      resource: {
        id: container.ContainerId
        partitionKey: {
          paths: [
            '/${container.PartionKey}'
          ]
          kind: 'Hash'
        }
        defaultTtl: 2592000 // 30 days
      }
      options: {
        throughput: 400
      }
    }
  }
]

// Function app storage

@description('''
Storage account name restrictions:
- Storage account names must be between 3 and 24 characters in length and may contain numbers and lowercase letters only.
- Your storage account name must be unique within Azure. No two storage accounts can have the same name.
''')
@minLength(3)
@maxLength(24)
param storageAccountName string = toLower(replace('safn-${substring(serviceName, 0, 6)}${uniqueId}${env}', '-', ''))

@description('The storage account for the function app.')
resource storage_account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
    }
  }
  resource blobServices 'blobServices' = {
    name: 'default'
  }
}

resource blob_container_deployment_package 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_account::blobServices
  name: 'deployment-package'
  properties: {
    publicAccess: 'None'
  }
}

// Function app hosting plan

param hostingPlanName string = toLower('asp-${serviceName}-${uniqueId}-${env}')

resource hosting_plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  properties: {
    reserved: true // required only for linux
    maximumElasticWorkerCount: 20
  }
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

// Function app

@description('''
Function app name restrictions:
- The name must be a string of 2 to 60 characters. The name can include only alphanumeric characters, hyphens, and underscores.
- The name must begin with a letter or a number.
- The name cannot end with a hyphen or an underscore.
''')
@minLength(2)
@maxLength(60)
param functionAppName string = toLower('func-${serviceName}-${uniqueId}-${env}')

resource function_app 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    reserved: true // required only for linux
    httpsOnly: true
    serverFarmId: hosting_plan.id
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      ftpsState: 'FtpsOnly'
      minimumElasticInstanceCount: 1
      minTlsVersion: '1.2'
      linuxFxVersion: 'DOTNET-ISOLATED|8.0' // required only for linux
      use32BitWorkerProcess: false
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage_account.name
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: 'https://${storage_account.name}.blob.${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: 'https://${storage_account.name}.blob.${environment().suffixes.storage}/${blob_container_deployment_package.name}/${serviceName}'
        }
        {
          name: 'CosmosDocumentEndpoint'
          value: 'https://${database_account.name}.documents.azure.com:443/'
        }
        {
          name: 'CosmosDatabaseId'
          value: nosql_database.id
        }
        {
          name: 'CosmosContainerId'
          value: database_containers[0].id
        }
        {
          name: 'WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED'
          value: '1' // https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide#performance-optimizations
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'false'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'false'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: functionAppName
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage_account.listKeys().keys[0].value}'
        }
      ]
    }
  }
}

// Role Assignments

@description('''
Permits management of storage accounts. 
Provides access to the account key, which can be used to access data via Shared Key authorization.
Provides full access to Azure Storage blob containers and data.
''')
var storageAccountRoleDefinitions = [
  getRoleDefinitions()['Storage Account Contributor']
  getRoleDefinitions()['Storage Blob Data Owner']
]

resource function_app_role_assignment_to_storage_account 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleDefinitionId in storageAccountRoleDefinitions: {
    name: guid(storage_account.id, function_app.name, roleDefinitionId)
    scope: storage_account
    properties: {
      principalId: function_app.identity.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: roleDefinitionId
    }
  }
]

@description('Can read Azure Cosmos DB account')
var cosmosDbAccountReaderRole = getRoleDefinitions()['Cosmos DB Account Reader Role']

resource group_read_role_assignment_to_cosmos_db 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(database_account.name, groupId, cosmosDbAccountReaderRole)
  scope: database_account
  properties: {
    principalId: groupId
    principalType: 'Group'
    roleDefinitionId: cosmosDbAccountReaderRole
  }
}

var cosmosDbBuiltInDataReaderRole = getBuiltInSqlRole(database_account.name)['Cosmos DB Built-in Data Reader']
var cosmosDbBuiltInDataContributorRole = getBuiltInSqlRole(database_account.name)['Cosmos DB Built-in Data Contributor']

@description('''Assign 'Cosmos DB Built-in Data Reader' role for user group.''')
resource group_reader_role_assignment_to_cosmos_db 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosDbBuiltInDataReaderRole, groupId, database_account.id)
  parent: database_account
  properties: {
    principalId: groupId
    scope: database_account.id
    roleDefinitionId: cosmosDbBuiltInDataReaderRole
  }
}

@description('''Assign 'Cosmos DB Account Reader Role' to function app.''')
resource function_app_reader_role_assignment_to_cosmos 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(database_account.name, function_app.id, cosmosDbAccountReaderRole)
  scope: database_account
  properties: {
    principalId: function_app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cosmosDbAccountReaderRole
  }
}

@description('''Assign 'Cosmos DB Built-in Data Contributor' to function app.''')
resource function_app_contributor_sql_role_assignment_to_cosmos 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosDbBuiltInDataContributorRole, function_app.id, database_account.id)
  parent: database_account
  properties: {
    principalId: function_app.identity.principalId
    scope: database_account.id
    roleDefinitionId: cosmosDbBuiltInDataContributorRole
  }
}

param githubWorkflowAzurePrincipalId string

param storageBlobDataContributor string = getRoleDefinitions()['Storage Blob Data Contributor']

@description('''
Storage Blob Data Contributor role for pipeline to storage account.
This enables the pipeline to upload built artifact (the function app as a zipped file) 
to the function app storage account.
''')
resource pipeline_role_assignment_to_storage_account 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage_account.id, githubWorkflowAzurePrincipalId, storageBlobDataContributor)
  scope: storage_account
  properties: {
    principalId: githubWorkflowAzurePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: githubWorkflowAzurePrincipalId
  }
}

@description('Storage Blob Data Contributor role assignment for Group')
resource group_role_assignment_to_storage_account 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage_account.id, groupId, storageBlobDataContributor)
  scope: storage_account
  properties: {
    principalId: groupId
    principalType: 'Group'
    roleDefinitionId: storageBlobDataContributor
  }
}

output storageAccountName string = storage_account.name
output storageContainerName string = blob_container_deployment_package.name
output functionAppName string = function_app.name
