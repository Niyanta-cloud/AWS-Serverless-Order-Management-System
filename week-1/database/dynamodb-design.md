# DynamoDB design

Terraform creates the orders table with on-demand billing and server-side encryption. Customers never connect directly to DynamoDB. Each Lambda uses its own IAM execution role with only the required table permissions.

## Base table

- Partition key: `orderId` (string, generated UUID)
- No sort key

| Attribute | Key role | Stored value / purpose |
|---|---|---|
| `orderId` | Table partition key | Generated unique order ID; identifies an order for direct get, update, and delete operations. |
| `customerId` | GSI partition key | The authenticated customer's Cognito `sub`; associates the order with its owner. Clients do not supply this value. |
| `createdAtOrder` | GSI sort key | Creation timestamp combined with the order ID; sorts a customer's orders newest first. |
| `items` | Regular attribute | List of product IDs and quantities in the order. |
| `totalAmount` | Regular attribute | Positive numeric order total supplied by the API client for this learning project. |
| `status` | Regular attribute | Current order state, initially `PENDING`. |
| `version` | Regular attribute | Starts at `1`; increments after each successful status update and protects against stale updates. |
| `createdAt` | Regular attribute | Order creation timestamp in UTC. |
| `updatedAt` | Regular attribute | Timestamp of the latest successful status update. |

DynamoDB does not define fixed columns for regular attributes; each item stores its own attributes. The table and GSI keys are defined in Terraform. The Create Lambda reads the validated Cognito `sub` claim and stores it as `customerId`.

## Global secondary index

- Name: `CustomerCreatedIndex`
- Partition key: `customerId` (string, Cognito `sub`)
- Sort key: `createdAtOrder` (string, `createdAt#orderId`)
- Projection: all attributes
- Query direction: descending, with pagination

The GSI efficiently lists only the signed-in customer's orders without scanning the table. GSI reads are eventually consistent. API Lambdas also verify order ownership when retrieving, updating, or deleting an item. Update and delete writes include `customerId` in their DynamoDB conditions so a request cannot change another customer's order.

Status updates also condition the write on the expected current status and version. This makes the owner, lifecycle, and concurrency checks part of one atomic DynamoDB update. Deletion is permanent and removes the item from the table and its GSI.

## Example item

```json
{
  "orderId": "generated-uuid",
  "customerId": "cognito-sub-uuid",
  "createdAtOrder": "2026-11-04T10:30:00.000Z#generated-uuid",
  "items": [
    { "productId": "P100", "quantity": 2 }
  ],
  "totalAmount": 49.98,
  "status": "PENDING",
  "version": 1,
  "createdAt": "2026-11-04T10:30:00.000Z",
  "updatedAt": "2026-11-04T10:30:00.000Z"
}
```
