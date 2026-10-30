# Transition rules

| From | To | Allowed |
|---|---|---|
| PENDING | CONFIRMED | Yes |
| PENDING | CANCELLED | Yes |
| CONFIRMED | PROCESSING | Yes |
| CONFIRMED | CANCELLED | Yes |
| PROCESSING | SHIPPED | Yes |
| SHIPPED | DELIVERED | Yes |
| any other pair | - | No |

Only pending and confirmed orders may be cancelled. A delivered or cancelled order cannot change state. The API requires `expectedStatus` and `expectedVersion`; the application validates the edge and DynamoDB checks the expected stored status and version atomically.
