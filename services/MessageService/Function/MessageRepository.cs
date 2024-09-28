using Microsoft.Azure.Cosmos;

namespace Function;

public class MessageRepository
{
    private Container _container;

    public MessageRepository(CosmosConfig config)
    {
        _container = config.CosmosClient.GetContainer(config.DatabaseId, config.ContainerId);
    }

    public async Task Save(CosmosAwareMessage cosmosAwareMessage)
    {
        await _container.UpsertItemAsync(cosmosAwareMessage, cosmosAwareMessage.PartitionKey, new ItemRequestOptions{
            IfMatchEtag = cosmosAwareMessage.ETag
        });
    }
}

public class CosmosConfig
{
    public CosmosConfig(CosmosClient cosmosClient, string databaseId, string containerId)
    {
        CosmosClient = cosmosClient;
        DatabaseId = databaseId;
        ContainerId = containerId;
    }

    public CosmosClient CosmosClient { get; }
    public string DatabaseId { get; }
    public string ContainerId { get; }
}