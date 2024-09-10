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

// Role Assignments

@description('Can read Azure Cosmos DB account')
var cosmosDbAccountReaderRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8')

resource group_read_role_assignment_to_cosmos_db 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(database_account.name, groupId, cosmosDbAccountReaderRole)
  scope: database_account
  properties: {
    principalId: groupId
    principalType: 'Group'
    roleDefinitionId: cosmosDbAccountReaderRole
  }
}
