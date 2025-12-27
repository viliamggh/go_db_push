# go_db_push

Transaction data processor service that reads blob files and upserts to Azure SQL Database.

## Architecture

```
┌─────────────────────┐     BlobCreated      ┌─────────────────────┐
│   Azure Storage     │ ─────────────────────▶│    go_db_push       │
│   (raw container)   │      Event Grid       │   Container App     │
└─────────────────────┘                       └──────────┬──────────┘
                                                         │
                                                         │ SQL Upsert
                                                         ▼
                                              ┌─────────────────────┐
                                              │   Azure SQL DB      │
                                              │   (Transactions)    │
                                              └─────────────────────┘
```

This service is triggered by Event Grid when new blobs are created in the storage account:
1. Receives `BlobCreated` event via webhook
2. Downloads the blob (JSON transaction file from FIO Bank API)
3. Parses transactions
4. Upserts to Azure SQL Database

## Dependencies

| Resource | Source | Description |
|----------|--------|-------------|
| Storage Account | fin_az_core | Blob storage for transaction files |
| SQL Database | fin_az_core | Transaction data store |
| Key Vault | fin_az_core | SQL credentials |
| ACR | fin_az_core | Container registry |
| Managed Identity | fin_az_core | Shared app identity |

**Upstream service**: `go_fio_pull` creates the blobs that trigger this service.

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check for Container App probes |
| `/blobCreated` | POST | Event Grid webhook for blob events |

## Environment Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `AZURE_CLIENT_ID` | Managed identity client ID | Terraform |
| `AZURE_TENANT_ID` | Azure tenant ID | Terraform |
| `STORAGE_ACCOUNT_URL` | Blob storage endpoint | Terraform (from fin_az_core) |
| `STORAGE_CONTAINER_NAME` | Container name (default: `raw`) | Terraform |
| `AZURE_SQL_SERVER_NAME` | SQL server name (without .database.windows.net) | Terraform (from fin_az_core) |
| `AZURE_SQL_DATABASE_NAME` | Database name | Terraform (from fin_az_core) |
| `SQL_USERNAME` | SQL user (`app_user`) | Terraform |
| `SQL_PASSWORD` | SQL password | Key Vault secret |

## Deployment

### Initial Setup

1. Run `infra_base.sh` to create Azure resources (RG, identity, TF state storage)
2. Add CI/CD identity principal ID to `fin_az_core/terraform/terraform.tfvars`:
   ```hcl
   external_cicd_identities = {
     "go_db_push" = "<principal-id>"
   }
   ```
3. Deploy fin_az_core to grant permissions
4. Push to main branch to trigger deployment

### CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yaml`) runs on push to `main`:
1. **Build**: Builds Docker image and pushes to shared ACR
2. **Deploy**: Terraform apply for Container App and Event Grid subscription

### GitHub Variables Required

Set by `infra_base.sh`:
- `UAMI_ID` - CI/CD identity client ID
- `TENANT_ID` - Azure tenant ID
- `SUB_ID` - Subscription ID
- `RG_NAME` - Resource group name
- `STORAGE_ACCOUNT_NAME` - TF state storage
- `CONTAINER_NAME` - TF state container
- `PROJECT_NAME_NODASH` - Project identifier

## Local Development

```bash
# Set environment variables
export STORAGE_ACCOUNT_URL="https://safinazcore251027dev.blob.core.windows.net/"
export STORAGE_CONTAINER_NAME="raw"
export AZURE_SQL_SERVER_NAME="sqlsrv-finazcore251027-dev-neu"
export AZURE_SQL_DATABASE_NAME="sqldb-finazcore251027-dev"
export SQL_USERNAME="app_user"
export SQL_PASSWORD="<from-keyvault>"

# Run the service
cd src && go run .
```

## Testing

Upload a test blob to trigger Event Grid:
```bash
az storage blob upload \
  --account-name safinazcore251027dev \
  --container-name raw \
  --name "transactions_test.json" \
  --file test_transactions.json \
  --auth-mode key
```

Check container logs:
```bash
az containerapp logs show \
  --name godbpush251227aca \
  --resource-group godbpush251227-rg \
  --tail 50
```

## Project Structure

```
go_db_push/
├── .github/workflows/
│   └── deploy.yaml           # CI/CD pipeline
├── src/
│   ├── main.go               # Application code
│   ├── Dockerfile            # Container build
│   ├── go.mod
│   └── go.sum
├── terraform/
│   ├── main.tf               # Backend, providers, remote state
│   ├── variables.tf          # Variable definitions
│   ├── container_app.tf      # Container App resource
│   └── event.tf              # Event Grid subscription
├── .infra-refs.yaml          # Cross-repo infrastructure references
├── infra_base.sh             # Initial Azure setup script
├── test_transactions.json    # Sample test data
└── README.md
```
