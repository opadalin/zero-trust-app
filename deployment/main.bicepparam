using './main.bicep'

param tags = {
  contributors: groupId
  app: serviceName
  env: env
}
param serviceName = 'shared'
param env = 'dev'
param uniqueId = substring(uniqueString(serviceName, env), 0, 5)
param groupId = 'c307debe-32cb-4e3b-8b07-34a1ed6b2002'

param githubWorkflowAzurePrincipalId =  '1bacf447-39ee-4e8a-b421-c0f233e93a0a'
