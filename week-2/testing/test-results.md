# Test results template

Fill this in with results from your own AWS deployment. Do not claim a case passed until you have run it and captured the response.

### Test Results Summary
method “$apiUrl/orders/…”

All 9 test scenarios passed successfully:


| # | Test | Method / Endpoint | Expected Result | Result |
|---|------|-------------------|-----------------|--------|
| 1 | Create a new order | `POST /orders”` | HTTP 201  | ✅ Pass |
| 2 | Retrieve an order by ID | ` GET /orders/$orderId` | HTTP 200    | ✅ Pass |
| 3 | List all orders | `GET /orders?customerId=... ` | HTTP 200   | ✅ Pass |
| 4 | Valid status transition (`PENDING` → `CONFIRMED`) | `PATCH /orders/{orderId}/status` | HTTP 200    | ✅ Pass |
| 5 | Invalid status transition (`CONFIRMED` → `PENDING`) | `PATCH /orders/{orderId}/status` | HTTP 400  | ✅ Pass |
| 6 |  Delete the order  | `DELETE /orders/$orderId` | HTTP 200  | ✅ Pass |
| 7 | Missing order  | `GET /orders/does-not-exist-1234` | HTTP 404  | ✅ Pass |
| 8 | Unauthorized request  | `GET /orders/$orderId` | HTTP 401/403  | ✅ Pass |
| 9 | Stale status update   | `PATCH /orders/$orderId/status` | HTTP 409  | ✅ Pass |


