---
operator: operators.ExternalTable
source_objects:
  - "mst/processed/customer_funding_source/*"
destination_project_dataset_table: "payments.customer_funding_source"
skip_leading_rows: 1
schema_fields:
  - name: funding_source_id
    type: STRING
  - name: funding_source_vault_id
    type: STRING
  - name: customer_id
    type: STRING
  - name: bin
    type: STRING
  - name: masked_pan
    type: STRING
  - name: card_scheme
    type: STRING
  - name: issuer
    type: STRING
  - name: issuer_country
    type: STRING
  - name: form_factor
    type: STRING
  - name: principal_customer_id
    type: STRING
  - name: calitp_extracted_at
    type: DATE
---
