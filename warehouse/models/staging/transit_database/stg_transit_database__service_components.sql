{{ config(materialized='table') }}

WITH
stg_transit_database__service_components AS (
    {{ get_latest_external_data(
        external_table_name = source('airtable', 'transit_technology_stacks__service_components'),
        columns = 'dt DESC, time DESC'
        ) }}
)

SELECT * EXCEPT(name), name as service_component_name FROM stg_transit_database__service_components
