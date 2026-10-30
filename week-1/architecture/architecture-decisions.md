# Architecture decisions

## API Gateway + Lambda

API Gateway provides managed HTTPS routing, request entry, and IAM authorization. Lambda runs stateless handlers on demand and avoids an always-on application server. EC2 could support long-running processes and custom runtime control, but requires instance maintenance, scaling, and idle capacity management. Lambda has execution limits, cold-start considerations, and service quotas.

## DynamoDB on-demand

The system's access patterns are known and key-oriented. DynamoDB provides managed availability and scales without running database servers. RDS would be preferable for relational joins, ad hoc reporting, or complex transactional constraints, but adds relational modeling and capacity/cost decisions beyond this project's needs. DynamoDB requires designing indexes around access patterns and is less flexible for arbitrary queries.

## Customer index and query

The base key supports direct order lookup by ID. A GSI supports listing by customer and creation time. A table scan was rejected because its work grows with all table items even when one customer's data is requested. The trade-off is extra index storage/write work and eventual consistency on GSI reads.

## Three functions

Create, read/list, and status update functions separate responsibilities and allow distinct execution roles. A single function/router would reduce deployment resources but combine permissions and code paths. The separate functions share a small Python module for consistent validation and data access.

## Lifecycle and concurrency

Application logic owns the allowed-transition map. DynamoDB conditional updates verify both expected state and version atomically, preventing a stale request from overwriting a concurrent update. A transaction is unnecessary for a single-item state change.

## Authentication limitation

AWS_IAM authorization protects API methods for trusted AWS identities using SigV4. It is straightforward for service-to-service and learning use. A public customer app should use a customer identity provider and enforce that each caller can read only their own customer ID; API authentication alone does not prove that a supplied customerId belongs to the caller.
