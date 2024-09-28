
@export()
func getRoleDefinitions() object => {
  'Storage Account Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  'Storage Blob Data Owner': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  'Storage Blob Data Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  'Cosmos DB Account Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8')
}

@export()
func getBuiltInSqlRole(databaseAccountName string) object => {
  'Cosmos DB Built-in Data Reader': '/${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${databaseAccountName}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001'
  'Cosmos DB Built-in Data Contributor': '/${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${databaseAccountName}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
}
