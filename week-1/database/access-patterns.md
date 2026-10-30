# Access patterns

| Use case | DynamoDB operation | Key/index | Scan? |
|---|---|---|---|
| Retrieve one order by ID | `GetItem` | Base key `orderId` | No |
| List a customer's orders | `Query` | `CustomerCreatedIndex`, `customerId`, descending sort key | No |
| Create order | `PutItem` with attribute-not-exists condition | Base key `orderId` | No |
| Update state | `UpdateItem` with status/version condition | Base key `orderId` | No |

Listing without a customer key is intentionally unsupported. A scan reads across unrelated orders and its work grows with table size. Pagination uses DynamoDB `LastEvaluatedKey` encoded as an opaque URL-safe token.
