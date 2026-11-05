# DynamoDB design

Table name is generated from the Terraform name prefix. The table uses on-demand billing and server-side encryption.

## Base table

- Partition key: `orderId` (string, UUID)
- No sort key

| Attribute | Key role | Stored value / purpose |
|---|---|---|
| `orderId` | Table partition key | Generated unique order ID; identifies an order for direct get, update, and delete operations. |
| `customerId` | GSI partition key | Customer identifier; groups orders for the customer-history query. |
| `createdAtOrder` | GSI sort key | Creation timestamp combined with the order ID; sorts a customer's orders newest first. |
| `items` | Regular attribute | List of product IDs and quantities in the order. |
| `totalAmount` | Regular attribute | Positive numeric order total. |
| `status` | Regular attribute | Current order state, initially `PENDING`. |
| `version` | Regular attribute | Starts at `1`; increments after each successful status update and protects against stale updates. |
| `createdAt` | Regular attribute | Order creation timestamp in UTC. |
| `updatedAt` | Regular attribute | Timestamp of the latest successful status update. |

DynamoDB does not define fixed columns for regular attributes; those attributes are stored on each item. The table and GSI keys are defined in Terraform, while the Lambda writes these attributes when creating and updating orders.

## Global secondary index

- Name: `CustomerCreatedIndex`
- Partition key: `customerId` (string)
- Sort key: `createdAtOrder` (string, `createdAt#orderId`)
- Projection: all attributes
- Query direction: descending, with pagination

The GSI makes a customer's history efficient without scanning the table. GSI reads are eventually consistent. A future design could add a separate administrative access pattern, but should only add indexes when a concrete query requires them.

Deleting an order uses its base-table `orderId` key with a condition that the item exists. Deletion is permanent and removes the item from the table and its GSI; it does not require a new key or index.

## Example item

```json
{
  "orderId": "generated-uuid",
  "customerId": "C1001",
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
