# API documentation

See `endpoints.md` for the endpoint table. All requests use HTTPS and AWS Signature Version 4 (SigV4). JSON request bodies use `Content-Type: application/json`.

## Create

`POST /orders`

```json
{"customerId":"C1001","items":[{"productId":"P100","quantity":2}],"totalAmount":49.98}
```

`customerId` must be a non-empty string, `items` must contain 1-50 entries, each product ID must be non-empty and quantity a positive integer, and `totalAmount` must be a finite positive number. The service generates an ID and timestamps, sets `PENDING`, and returns the stored order with `201`.

## Retrieve one

`GET /orders/{orderId}` returns the order or `404`.

## List

`GET /orders?customerId=C1001&limit=20&nextToken=...` returns `items` and optionally `nextToken`. `limit` is from 1 through 100 and defaults to 20. The token is an opaque, URL-safe encoding of the DynamoDB query cursor. Results are newest first. The GSI is eventually consistent.

## Update status

`PATCH /orders/{orderId}/status`

```json
{"expectedStatus":"PENDING","expectedVersion":1,"newStatus":"CONFIRMED"}
```

Both status values must be known. The transition must be allowed by the state machine and `expectedStatus` plus `expectedVersion` must match the current database values. Use the status and version returned by the last read/update. A stale/conflicting state returns `409`.

## Error codes

- `VALIDATION_ERROR` - malformed body, missing/invalid fields, or query parameters.
- `INVALID_TRANSITION` - requested lifecycle edge is disallowed.
- `ORDER_NOT_FOUND` - the order ID does not exist.
- `STATUS_CONFLICT` - expected state/version no longer matches stored state.
- `INTERNAL_ERROR` - unexpected backend failure; the response does not expose internal exception details.