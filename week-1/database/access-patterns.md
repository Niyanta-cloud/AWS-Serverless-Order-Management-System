# Access patterns

Lambdas use their IAM execution roles to access DynamoDB. For customer-scoped operations, the customer key is the authenticated customer's Cognito `sub` claim. The API never accepts a caller-selected customer ID as proof of ownership.

| Use case | DynamoDB operation | Key / condition | Scan? |
|---|---|---|---|
| Retrieve one owned order | `GetItem`, then compare the item's `customerId` with the token `sub` | Base key `orderId` | No |
| List signed-in customer's orders | `Query` | `CustomerCreatedIndex`: `customerId = sub`, newest `createdAtOrder` first | No |
| Create order | `PutItem` with `attribute_not_exists(orderId)` | Base key `orderId`; set `customerId` from token `sub` | No |
| Update owned order status | `UpdateItem` with owner, expected status, and expected version conditions | Base key `orderId`; `customerId`, status, and version must match | No |
| Delete owned order | `DeleteItem` with item-exists and owner conditions | Base key `orderId`; `customerId` must match token `sub` | No |

Global listing is intentionally unsupported. The customer key comes from the Cognito token rather than a query parameter. A scan reads unrelated orders and its work grows with table size. Pagination uses DynamoDB `LastEvaluatedKey` encoded as an opaque URL-safe token. GSI reads are eventually consistent.

After a successful create, the Create Lambda also publishes a compact `ORDER_CREATED` event to SQS for separate background processing. The SQS worker does not perform the customer-facing create response; the order is stored in DynamoDB and the API returns its `orderId`.
