---
operator: operators.ExternalTable
source_objects:
  - "mst/processed/micropayments/*"
destination_project_dataset_table: "payments.micropayments"
skip_leading_rows: 1
schema_fields:
    - name: micropayment_id
      type: STRING
    - name: aggregation_id
      type: STRING
    - name: participant_id
      type: STRING
    - name: customer_id
      type: STRING
    - name: funding_source_vault_id
      type: STRING
    - name: transaction_time
      type: TIMESTAMP
    - name: payment_liability
      type: STRING
    - name: charge_amount
      type: NUMERIC
    - name: nominal_amount
      type: NUMERIC
    - name: currency_code
      type: INTEGER
    - name: type
      type: STRING
    - name: charge_type
      type: STRING
    - name: calitp_extracted_at
      type: DATE
---
