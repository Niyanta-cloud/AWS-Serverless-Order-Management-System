# API demonstration cases

Use two confirmed Cognito customer accounts to check authentication and ownership. Send each API request with that customer's Cognito ID token. Do not claim a case passed until you run it against the deployed API and record its actual response.

| Case | Request / setup | Expected |
|---|---|---|
| Sign up and sign in | Confirm a Cognito user, then obtain an ID token | Cognito returns a token for the user |
| Unauthorized call | Call an API route without an ID token | `401 Unauthorized` from API Gateway |
| Create valid order | `POST /orders` with items and total, without `customerId` | `201`, `PENDING`, generated `orderId`, and token `sub` stored as `customerId` |
| Reject caller-selected customer | `POST /orders` with a `customerId` field | `400 VALIDATION_ERROR` |
| Retrieve owned order | `GET /orders/{orderId}` with its owner's token | `200` and matching order |
| Retrieve missing order | `GET /orders/does-not-exist` | `404 ORDER_NOT_FOUND` |
| Prevent cross-customer read | Customer B requests Customer A's order | `404 ORDER_NOT_FOUND` |
| Delete owned order | `DELETE /orders/{orderId}` with its owner's token | `200` deletion confirmation |
| Prevent cross-customer delete | Customer B deletes Customer A's order | `404 ORDER_NOT_FOUND`; order remains |
| Retrieve after delete | `GET` the deleted order ID as its owner | `404 ORDER_NOT_FOUND` |
| List own orders | `GET /orders?limit=20` with the customer's token | `200`; only that customer's orders and optional cursor |
| Valid state change | `PENDING`/version `1` to `CONFIRMED` on an owned order | `200` and updated version |
| Invalid transition | `PENDING` to `SHIPPED` on an owned order | `400 INVALID_TRANSITION` |
| Stale expected state/version | Repeat an update using `PENDING`/version `1` after confirmation | `409 STATUS_CONFLICT` |
| Invalid state name | Send `newStatus: BOGUS` | `400 VALIDATION_ERROR` |

The SQS worker handles a separate post-create event. Worker failure and DLQ alarm behavior are checked through CloudWatch/SQS monitoring, not through a different customer API response.
