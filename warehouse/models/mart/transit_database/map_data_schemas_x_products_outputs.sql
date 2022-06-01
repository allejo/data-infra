{{ config(materialized='table') }}

WITH stg_transit_database__data_schemas AS (
    SELECT * FROM {{ ref('stg_transit_database__data_schemas') }}
),

stg_transit_database__products AS (
    SELECT * FROM {{ ref('stg_transit_database__products') }}
),

map_data_schemas_x_products_outputs AS (
 {{ transit_database_many_to_many(
     table_a = 'stg_transit_database__data_schemas',
     table_a_id_col = 'id',
     table_a_id_col_name = 'data_schema_id',
     table_a_name_col = 'name',
     table_a_name_col_name = 'data_schema_name',
     table_a_join_col = 'output_products',
     table_b = 'stg_transit_database__products',
     table_b_id_col = 'id',
     table_b_id_col_name = 'product_id',
     table_b_name_col = 'name',
     table_b_name_col_name = 'product_name',
     table_b_join_col = 'output_components'
 ) }}
)

SELECT * FROM map_data_schemas_x_products_outputs
