# API Test Results (Cognito-Authenticated)

> All scenarios below were executed against the live AWS deployment (`eu-central-1`) using a verified Amazon Cognito User Pool JWT (`$idToken`) per [orderflow_cli_guide.md](orderflow_cli_guide.md).
 
## Test Environment
* **Region:** `eu-central-1`
* **Auth Flow:** Amazon Cognito `USER_PASSWORD_AUTH` (JWT `IdToken` passed via `--token $idToken`)
* **Base Endpoint:** `$apiUrl/orders`
* **Key Post-Cognito Behavior:** Customer identity is extracted from verified JWT claims on the backend rather than passed as an untrusted `customerId` query parameter.


| # | Test | Method / Endpoint | Expected Result | Result |
|---|------|-------------------|-----------------|--------|
| 1 | Create a new order | `POST /orders”` | HTTP 201  | ✅ Pass |
| 2 | Retrieve an order by ID | ` GET /orders/$orderId` | HTTP 200    | ✅ Pass |
| 3 | List the signed-in customer's orders | `GET /orders` | HTTP 200   | ✅ Pass |
| 4 | Valid status transition (`PENDING` → `CONFIRMED`) | `PATCH /orders/{orderId}/status` | HTTP 200    | ✅ Pass |
| 5 | Invalid status transition (`CONFIRMED` → `PENDING`) | `PATCH /orders/{orderId}/status` | HTTP 400  | ✅ Pass |
| 6 |  Delete the order  | `DELETE /orders/$orderId` | HTTP 200  | ✅ Pass |
| 7 | Missing order  | `GET /orders/does-not-exist-1234` | HTTP 404  | ✅ Pass |
| 8 | Unauthorized request  | `GET /orders/$orderId` | HTTP 401  | ✅ Pass |
| 9 | Stale status update   | `PATCH /orders/$orderId/status` | HTTP 409  | ✅ Pass |
| 10 | Another customer tries to read this customer's order | `GET /orders/{orderId}` with second customer's token | HTTP 404 | ✅ Pass  |


