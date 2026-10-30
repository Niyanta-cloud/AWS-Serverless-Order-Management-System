# DynamoDB design

Table name is generated from the Terraform name prefix. The table uses on-demand billing and server-side encryption.

## Base table

- Partition key: `orderId` (string, UUID)
- No sort key
- Item fields: `orderId`, `customerId`, `items`, `totalAmount`, `status`, `createdAt`, `updatedAt`, `version`

## Global secondary index

- Name: `CustomerCreatedIndex`
- Partition key: `customerId` (string)
- Sort key: `createdAtOrder` (string, `createdAt#orderId`)
- Projection: all attributes
- Query direction: descending, with pagination

The GSI makes a customer's history efficient without scanning the table. GSI reads are eventually consistent. A future design could add a separate administrative access pattern, but should only add indexes when a concrete query requires them.
