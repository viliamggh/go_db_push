# Event Grid subscription for blob created events
resource "azurerm_eventgrid_event_subscription" "blob_created" {
  name  = "blob-created-to-db-push"
  scope = local.storage_account_id

  webhook_endpoint {
    url = "https://${azurerm_container_app.db_push.latest_revision_fqdn}/blobCreated?code=${urlencode(data.azurerm_key_vault_secret.webhook_key.value)}"
  }

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${local.storage_container_name}/blobs/"
  }

  depends_on = [azurerm_container_app.db_push]
}
