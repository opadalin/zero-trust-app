using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Net;
using System.Text;
using Microsoft.Azure.Cosmos;
using Newtonsoft.Json;

namespace Function;

public class CreateMessage
{
    private readonly MessageRepository messageRepository;

    public CreateMessage(MessageRepository messageRepository)
    {
        this.messageRepository = messageRepository;
    }

    [Function(nameof(CreateMessage))]
    public async Task<HttpResponseData> Run([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "messages")]
    HttpRequestData req, FunctionContext functionContext)
    {
        var logger = functionContext.GetLogger<CreateMessage>();
        var response = req.CreateResponse(HttpStatusCode.Created);

        MessageRequest messageRequest = await req.ReadFromJsonAsync<MessageRequest>(functionContext.CancellationToken);
        Message message = new Message(
            Guid.NewGuid(), 
            messageRequest.MessagePayload, 
            messageRequest.MessageType, 
            DateTimeOffset.UtcNow
        );
        
        CosmosAwareMessage cosmosAwareMessage = new CosmosAwareMessage(message);

        await messageRepository.Save(cosmosAwareMessage);

        await response.WriteStringAsync("Created a message!\n", functionContext.CancellationToken, Encoding.UTF8);
        logger.LogInformation("Message was created.");
        return response;
    }
}

public record MessageRequest(string MessagePayload, string MessageType);

public record Message(
    [property: JsonProperty("messageId")] Guid MessageId,
    [property: JsonProperty("messagePayload")] string MessagePayload,
    [property: JsonProperty("messageType")] string MessageType,
    [property: JsonProperty("createdAt")] DateTimeOffset CreatedAt
);

public sealed record CosmosAwareMessage : Message
{
    [JsonConstructor]
    public CosmosAwareMessage(Guid MessageId, string MessagePayload, string MessageType, DateTimeOffset CreatedAt, string eTag) :
    base(MessageId, MessagePayload, MessageType, CreatedAt)
    {
        Id = MessageId.ToString("D");
        PartitionKey = new PartitionKey(MessageType);
        ETag = eTag;
    }

    public CosmosAwareMessage(Message message) :
    base(message.MessageId, message.MessagePayload, message.MessageType, message.CreatedAt)
    {
        Id = message.MessageId.ToString("D");
        PartitionKey = new PartitionKey(message.MessageType);
    }

    [JsonProperty("id")]
    public string Id { get; }

    [JsonIgnore]
    public PartitionKey PartitionKey { get; }

    [JsonProperty("_etag")]
    public string ETag { get; }
}
