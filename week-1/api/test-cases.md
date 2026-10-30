# API demonstration cases

Record actual status codes and responses after deploying in `../tests/test-results.md`.

| Case | Request | Expected |
|---|---|---|
| Create valid order | POST sample body | 201, PENDING, generated ID |
| Create missing customer | POST without `customerId` | 400 VALIDATION_ERROR |
| Retrieve existing | GET created ID | 200 and matching order |
| Retrieve missing | GET unknown ID | 404 ORDER_NOT_FOUND |
| List customer orders | GET with `customerId` | 200, items and optional cursor |
| List without customer | GET without query | 400 VALIDATION_ERROR |
| Valid state change | PENDING/version 1 to CONFIRMED | 200 and updated version |
| Invalid transition | PENDING to SHIPPED | 400 INVALID_TRANSITION |
| Stale expected state/version | expected PENDING/version 1 after confirmation | 409 STATUS_CONFLICT |
| Invalid state name | newStatus `BOGUS` | 400 VALIDATION_ERROR |
| Unauthorized call | request without valid SigV4 invoke permission | 401/403 from API Gateway |
