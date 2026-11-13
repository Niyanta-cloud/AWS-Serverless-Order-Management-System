# Architecture decisions

## API Gateway, Cognito, and Lambda

API Gateway provides managed HTTPS routing and validates Cognito user-pool ID tokens before invoking the API Lambdas. Cognito handles customer sign-up and sign-in. Each Lambda derives the customer ID from the validated token's `sub` claim and checks ownership, so clients cannot choose another customer's `customerId` in a request. Customers do not receive database credentials or direct DynamoDB access.

The four API handlers separate create, read/list, status update, and delete operations. A fifth Lambda handles post-create SQS events in the background. Lambda runs on demand and avoids an always-on application server. EC2 could support long-running processes and custom runtime control, but it requires instance maintenance, scaling, and idle-capacity management. Lambda has execution limits, cold starts, and service quotas.

IAM remains responsible for AWS service access: each Lambda assumes its own execution role with narrowly scoped permissions for the AWS services that function needs, such as DynamoDB, SQS, or CloudWatch Logs. Customer API requests use Cognito tokens rather than SigV4. Terraform still uses an AWS CLI identity to create and manage AWS resources.

## DynamoDB on-demand

The system's access patterns are known and key-oriented. DynamoDB provides managed availability and scales without running database servers. On-demand billing avoids selecting provisioned capacity for this learning project. RDS would be preferable for relational joins, ad hoc reporting, or complex transactional constraints, but adds relational modeling and capacity/cost decisions beyond these requirements. DynamoDB requires designing indexes around access patterns and is less flexible for arbitrary queries.

## Customer index and ownership checks

The base key supports direct order lookup by ID. The `CustomerCreatedIndex` GSI supports listing by authenticated customer and creation time. A table scan was rejected because its work grows with all table items even when one customer's data is requested. The trade-off is extra index storage/write work and eventual consistency on GSI reads.

Get operations compare the stored customer ID to the Cognito `sub`. Update and delete operations include the owner in DynamoDB conditions so a write cannot affect another customer's order. A missing order and an order owned by another customer both return `404 ORDER_NOT_FOUND` to avoid revealing whether someone else's order exists.

## Synchronous order creation and SQS

The Create Lambda writes the order to DynamoDB and returns the saved order ID through API Gateway. It also sends a compact post-create event to SQS. A worker Lambda processes the event separately; repeated processing failures move the message to a DLQ after five receives. This buffers background work and supports retries without making the customer wait for worker processing. The initial order request still depends on the Create Lambda and DynamoDB, so SQS does not absorb traffic for those synchronous steps.

## Lifecycle and concurrency

Application logic owns the allowed-transition map. DynamoDB conditional updates verify the order owner, expected state, and version atomically, preventing a stale request from overwriting a concurrent update. A transaction is unnecessary for a single-item state change.

## Monitoring and alerting

CloudWatch stores Lambda logs and monitors Lambda/API errors and duration, DynamoDB throttling, and DLQ messages. CloudWatch alarms publish to an SNS topic, which sends email after the subscription is confirmed. These alarms report service conditions; the worker's background processing is not the source of the create response or order ID.

## Authentication trade-offs

Cognito provides customer identity; it does not by itself enforce access to each order. The per-customer checks in Lambda use the authorizer-validated `sub`, never a client-supplied customer ID. The CLI learning flow uses a Cognito app client with password authentication. A customer-facing production application should use an appropriate sign-in flow such as OAuth authorization code with PKCE, protect tokens, and review rate limits, recovery, monitoring, backups, idempotency, and operational procedures.
