# OrderFlow: Terraform Configuration and Deployment Guide

This guide walks through configuring AWS credentials, managing Terraform workspaces, provisioning serverless cloud infrastructure, testing the REST API endpoints via PowerShell, monitoring CloudWatch logs, and tearing down resources.

---

### Step 1: Navigate to the Terraform Directory
Switch into the Terraform configuration folder from your terminal.

```powershell
cd terraform
```

---

### Step 2: Configure AWS Profile and Verify Credentials
Configure a dedicated AWS CLI profile named `orderflow`, set it in your environment session, and verify that the identity credentials resolve as expected.

```powershell
aws configure --profile orderflow
$env:AWS_PROFILE = "orderflow"
aws sts get-caller-identity
aws sts get-caller-identity --profile orderflow
```

---

### Step 3: Create and Switch to the AWS Workspace
Set up an isolated workspace named `aws` to maintain environment-specific state files.

```powershell
terraform workspace new aws
terraform workspace select aws
terraform workspace show
```

---

### Step 4: Initialize, Format-Check, and Validate Terraform
Confirm the active workspace, initialize providers and backend plugins, verify source formatting, and run syntax validation.

```powershell
terraform workspace show

# Initialize provider plugins and local backend
terraform init

# Check code formatting without applying changes
terraform fmt -check

# Validate configuration syntax and consistency
terraform validate
```

---

### Step 5: Generate and Review the Execution Plan
Preview the infrastructure additions and modifications using the example variables file.

```powershell
terraform plan -var-file="aws.tfvars.example"
```

---

### Step 6: Apply the Infrastructure Deployment
Execute the plan to deploy the DynamoDB table, API Gateway, and Lambda functions.

```powershell
terraform apply -var-file="aws.tfvars.example"
```

*Expected outputs will resemble:*
```text
api_url = "https://b4nr98645d.execute-api.eu-central-1.amazonaws.com/v1"
lambda_names = {
  "create" = "orderflow-demo-create"
  "delete" = "orderflow-demo-delete"
  "read"   = "orderflow-demo-read"
  "update" = "orderflow-demo-update"
}
orders_table_name = "orderflow-demo-orders"
```

---

### Step 7: Export the API URL and Return to the Root Directory
Store the deployed API endpoint URL into a session variable and return to the project root.

```powershell
$env:AWS_PROFILE = "orderflow"
$apiUrl = terraform output -raw api_url
cd ..
```

---

### Step 8: Verify the Working Directory
Confirm your terminal prompt has returned to the root folder of the project:

```text
...\week-2>
```

---

### Step 9: Install API Helper Dependencies
Install the required Python packages for running the API test harness.

```powershell
python -m pip install -r examples/requirements.txt
```

---

### Step 10: Create Orders (HTTP 201 Created)
Create sample orders using the JSON request utility. Capture the generated `orderId` from the response.

**Order 1:**
```powershell
$body = @{
    customerId = "C1001"
    items = @(@{ productId = "P100"; quantity = 2 })
    totalAmount = 41.98
} | ConvertTo-Json -Depth 5 -Compress

$body | python examples/request_api.py POST "$apiUrl/orders" --body-stdin
```

**Order 2:**
```powershell
$body = @{
    customerId = "C1001"
    items = @(@{ productId = "P100"; quantity = 2 })
    totalAmount = 41.98
} | ConvertTo-Json -Depth 5 -Compress

$body | python examples/request_api.py POST "$apiUrl/orders" --body-stdin
```

---

### Step 11: Retrieve Order by ID (HTTP 200 OK)
Replace `PASTE_ORDER_ID_HERE` with the ID obtained from Step 10 and query the record.

```powershell
$orderId = "PASTE_ORDER_ID_HERE"
python examples/request_api.py GET "$apiUrl/orders/$orderId"
```

---

### Step 12: List Customer Orders (HTTP 200 OK)
Query all orders associated with customer `C1001`.

```powershell
python examples/request_api.py GET "$apiUrl/orders?customerId=C1001&limit=20"
```

---

### Step 13: Perform a Valid Order Status Update (HTTP 200 OK)
Update a new order from `PENDING` (version 1) to `CONFIRMED`.

```powershell
$body = @{ expectedStatus = "PENDING"; expectedVersion = 1; newStatus = "CONFIRMED" } | ConvertTo-Json -Compress
$body | python examples/request_api.py PATCH "$apiUrl/orders/$orderId/status" --body-stdin
```

---

### Step 14: Test Invalid State Transition (HTTP 400 Bad Request)
Verify that illegal state jumps (such as direct transition from `PENDING` to `DELIVERED`) are rejected.

```powershell
$body = @{ expectedStatus = "PENDING"; expectedVersion = 1; newStatus = "DELIVERED" } | ConvertTo-Json -Compress
$body | python examples/request_api.py PATCH "$apiUrl/orders/$orderId/status" --body-stdin
```

---

### Step 15: Test Stale Version Update Conflict (HTTP 409 Conflict)
Verify optimistic locking: sending a status change request with outdated status/version attributes triggers a `409 STATUS_CONFLICT`.

```powershell
# Attempt to re-apply an update assuming PENDING v1 on an already modified order
$body = @{ expectedStatus = "PENDING"; expectedVersion = 1; newStatus = "CONFIRMED" } | ConvertTo-Json -Compress
$body | python examples/request_api.py PATCH "$apiUrl/orders/$orderId/status" --body-stdin
```

---

### Step 16: Test Querying Non-Existent Order (HTTP 404 Not Found)
Verify proper error handling when requesting an unknown order identifier.

```powershell
python examples/request_api.py GET "$apiUrl/orders/does-not-exist-12345"
```

---

### Step 17: Test Unauthorized Request (HTTP 401 / 403 Forbidden)
Clear the AWS profile variable temporarily to simulate an unauthenticated request.

```powershell
Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
python examples/request_api.py GET "$apiUrl/orders/$orderId"
```

---

### Step 18: Delete an Order (HTTP 200 OK)
Restore the AWS profile and permanently remove the order item from DynamoDB.

```powershell
$env:AWS_PROFILE = "orderflow"
python examples/request_api.py DELETE "$apiUrl/orders/$orderId"
```

---

### Step 19: Return to the Terraform Directory
Navigate back to the infrastructure root to inspect logs or tear down resources.

```powershell
cd terraform
```

---

### Step 20: Inspect AWS Lambda CloudWatch Logs
Monitor real-time execution logs for the Lambda microservices.

**Follow logs for the Create function (Press `Ctrl+C` to exit):**
```powershell
aws logs tail "/aws/lambda/orderflow-demo-create" --since 30m --follow --profile orderflow --region eu-central-1
```
*(Replace `create` with `read`, `update`, or `delete` to view other function logs)*

**List all OrderFlow CloudWatch log groups:**
```powershell
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/orderflow-demo-" --query "logGroups[].logGroupName" --output table
```

---

### Step 21: Configure Terraform Debug Logging (Optional)
To troubleshoot low-level provider or HTTP communication issues, activate detailed CLI logging.

```powershell
# Set log verbosity to INFO or DEBUG
$env:TF_LOG = "INFO"
terraform plan -var-file="aws.tfvars.example"

# For maximum trace output:
$env:TF_LOG = "DEBUG"
terraform plan -var-file="aws.tfvars.example"

# Disable debug logging when finished
Remove-Item Env:TF_LOG
```

---

### Step 22: Destroy AWS Infrastructure
Clean up and tear down all provisioned cloud resources to prevent ongoing AWS charges.

```powershell
terraform destroy -var-file="aws.tfvars.example"
```