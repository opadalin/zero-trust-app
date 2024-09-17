using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Azure;
using Function;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices((context, services) =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        IConfiguration config = context.Configuration;
        services.AddScoped<TokenCredential>(_ => new DefaultAzureCredential());
        services.AddAzureClients(clientBuilder =>
        {
            clientBuilder.AddClient<CosmosClient, CosmosClientOptions>((_, tokenCredential, _) =>
            new CosmosClient(config.GetValue<string>("CosmosDocumentEndpoint"), tokenCredential, new CosmosClientOptions
            {
                SerializerOptions = new CosmosSerializationOptions
                {
                    PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase,
                    Indented = true
                },
                ConsistencyLevel = ConsistencyLevel.Session
            }));
        });
        services.AddSingleton(s => 
            new CosmosConfig(
                s.GetService<CosmosClient>(), 
                config.GetValue<string>("CosmosDatabaseId"), 
                config.GetValue<string>("CosmosContainerId"))
        );
        services.AddSingleton(s => new MessageRepository(s.GetService<CosmosConfig>()));
    })
    .Build();

host.Run();
