# Endpoints

Every route requires a valid Cognito ID token in the `Authorization` header. API Gateway validates the token; the Lambda uses its customer `sub` claim to enforce ownership. Clients must not provide a `customerId`.

| Method and path | Purpose | Success |
|---|---|---|
| `POST /orders` | Create an order for the signed-in customer | `201` |
| `GET /orders/{orderId}` | Get one of the signed-in customer's orders | `200` |
| `DELETE /orders/{orderId}` | Permanently delete one of the signed-in customer's orders | `200` |
| `GET /orders?limit=20&nextToken=...` | List the signed-in customer's orders | `200` |
| `PATCH /orders/{orderId}/status` | Change status of an owned order | `200` |

Missing or invalid tokens are rejected by API Gateway with HTTP `401`. Order IDs that do not exist or belong to another customer return HTTP `404`. Invalid input or lifecycle transitions return `400`; stale status/version writes return `409`; unexpected backend errors return `500`.

The Create Lambda saves the order and returns its generated `orderId` through API Gateway. It also sends a post-create event to SQS for background processing. The worker and DLQ do not change the customer-facing routes.
