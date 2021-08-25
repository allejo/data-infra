---
operator: operators.ExternalTable
source_objects:
  - "mst/processed/micropayment-device-transactions/*"
destination_project_dataset_table: "payments.micropayment_device_transactions"
skip_leading_rows: 1
schema_fields:
  - name: littlepay_transaction_id
    type: STRING
  - name: micropayment_id
    type: STRING
  - name: calitp_extracted_at
    type: DATE
---
