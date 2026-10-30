# Endpoints

All endpoints require AWS IAM SigV4 authorization.

| Method and path | Purpose | Success |
|---|---|---|
| `POST /orders` | Create an order | `201` |
| `GET /orders/{orderId}` | Get one order | `200` |
| `GET /orders?customerId=...` | List a customer's orders | `200` |
| `PATCH /orders/{orderId}/status` | Change order state | `200` |

Errors use a JSON body: `{"error":{"code":"...","message":"..."}}`. The API returns `400` for invalid input/transition, `401` or `403` for authorization failures from API Gateway, `404` for missing orders, `409` for conflicting status, `500` for unexpected service errors, and `502` for invalid backend responses where API Gateway applies that mapping.