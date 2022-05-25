{{ config(materialized='table') }}

WITH
stg_transit_database__products AS (
    {{ get_latest_external_data(
        external_table_name = source('airtable', 'transit_technology_stacks__products'),
        columns = 'dt DESC, time DESC'
        ) }}
)

SELECT * EXCEPT(name), name AS product_name FROM stg_transit_database__products
