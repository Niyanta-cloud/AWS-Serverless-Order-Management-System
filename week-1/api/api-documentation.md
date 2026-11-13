# API documentation

All API methods require an Amazon Cognito user-pool ID token in the `Authorization` header. API Gateway validates the token before invoking a Lambda. Each Lambda uses the trusted token `sub` claim as the customer ID and enforces order ownership. Do not send a `customerId` in a request body or use one to select another customer's orders.

Requests use HTTPS and JSON request bodies use `Content-Type: application/json`. The CLI helper sends the Cognito token with `--token $idToken`.

## Create

`POST /orders`

```json
{"items":[{"productId":"P100","quantity":2}],"totalAmount":49.98}
```

`items` must contain 1–50 entries; each product ID must be a non-empty string and quantity a positive integer. `totalAmount` must be a finite positive number. Do not include `customerId`; the Create Lambda sets it from the authenticated token's `sub`. The Lambda saves the order with a generated ID and timestamps, sets `PENDING`, then publishes a post-create event to SQS. The API returns the saved order and `orderId` with HTTP `201`; it does not wait for the background worker to process the event.

## Retrieve one

`GET /orders/{orderId}`

Returns the order with HTTP `200` only if it belongs to the signed-in customer. A missing order or one owned by another customer returns `404 ORDER_NOT_FOUND`.

## Delete

`DELETE /orders/{orderId}`

Permanently deletes the order only if it belongs to the signed-in customer. It returns HTTP `200` with a confirmation and the deleted ID. A missing or other customer's order returns `404 ORDER_NOT_FOUND`.

## List

`GET /orders?limit=20&nextToken=...`

Returns only the signed-in customer's orders as `items`, with an optional `nextToken`. `limit` is from 1 through 100 and defaults to 20. Customer identity comes from the validated token, not a query parameter. Results are newest first through the `CustomerCreatedIndex` GSI, which is eventually consistent. The token is an opaque, URL-safe encoding of the DynamoDB query cursor.

## Update status

`PATCH /orders/{orderId}/status`

```json
{"expectedStatus":"PENDING","expectedVersion":1,"newStatus":"CONFIRMED"}
```

Both status values must be known and the transition must be allowed. The order must belong to the signed-in customer. `expectedStatus` and `expectedVersion` must match the current database values; use the status and version returned by the last read/update. A stale or conflicting state returns HTTP `409 STATUS_CONFLICT`.

## Error codes

- `VALIDATION_ERROR` - malformed body or invalid fields/values. A request body containing `customerId` is rejected.
- `INVALID_TRANSITION` - requested lifecycle change is disallowed.
- `ORDER_NOT_FOUND` - the order does not exist or is not owned by the signed-in customer.
- `STATUS_CONFLICT` - expected state/version no longer matches the stored order.
- `INTERNAL_ERROR` - unexpected backend failure; the response does not expose internal exception details.
- Missing or invalid Cognito token - API Gateway rejects the request with HTTP `401` and `Unauthorized`.
