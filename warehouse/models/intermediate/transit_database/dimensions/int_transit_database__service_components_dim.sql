{{ config(materialized='table') }}

WITH latest_service_components AS (
    SELECT *
    FROM {{ ref('int_transit_database__service_components_unnested') }}
),

dim_components AS (
    SELECT * FROM {{ ref('int_transit_database__components_dim') }}
),

dim_services AS (
    SELECT * FROM {{ ref('int_transit_database__services_dim') }}
),

dim_products AS (
    SELECT * FROM {{ ref('int_transit_database__products_dim') }}
),

-- TODO: make this table actually historical
historical AS (
    SELECT
        *,
        TRUE AS _is_current,
        CAST(universal_first_val AS TIMESTAMP) AS _valid_from,
        {{ make_end_of_valid_range('CAST("2099-01-01" AS TIMESTAMP)') }} AS _valid_to
    FROM latest_service_components
),

-- join SCD tables: https://sqlsunday.com/2014/11/30/joining-two-scd2-tables/
join_services AS (
    SELECT
        historical.name,
        historical.id AS original_record_id,
        dim_services.key AS service_key,
        dim_services.name AS service_name,
        component_key,
        product_key,
        historical.ntd_certified,
        historical.product_component_valid,
        historical.notes,
        (historical._is_current AND dim_services._is_current) AS _is_current,
        GREATEST(historical._valid_from, dim_services._valid_from) AS _valid_from,
        LEAST(historical._valid_to, dim_services._valid_to) AS _valid_to
    FROM historical
    INNER JOIN dim_services
        ON historical.service_key = dim_services.original_record_id
        AND historical._valid_from < dim_services._valid_to
        AND historical._valid_to > dim_services._valid_from
),

join_products AS (
    SELECT
        join_services.original_record_id,
        join_services.name,
        service_key,
        service_name,
        dim_products.key AS product_key,
        dim_products.name AS product_name,
        component_key,
        ntd_certified,
        product_component_valid,
        join_services.notes,
        (join_services._is_current AND dim_products._is_current) AS _is_current,
        GREATEST(join_services._valid_from, dim_products._valid_from) AS _valid_from,
        LEAST(join_services._valid_to, dim_products._valid_to) AS _valid_to
    FROM join_services
    INNER JOIN dim_products
        ON join_services.product_key = dim_products.original_record_id
        AND join_services._valid_from < dim_products._valid_to
        AND join_services._valid_to > dim_products._valid_from
),

dim_service_components AS (
    SELECT
        {{ dbt_utils.surrogate_key(['join_products.original_record_id',
            'service_key',
            'product_key',
            'dim_components.key',
            'GREATEST(join_products._valid_from, dim_components._valid_from)']) }} AS key,
        join_products.name,
        join_products.original_record_id,
        service_key,
        service_name,
        product_key,
        product_name,
        dim_components.key AS component_key,
        dim_components.name AS component_name,
        ntd_certified,
        product_component_valid,
        join_products.notes,
        (join_products._is_current AND COALESCE(dim_components._is_current, TRUE)) AS _is_current,
        GREATEST(join_products._valid_from, COALESCE(dim_components._valid_from, '1900-01-01')) AS _valid_from,
        LEAST(join_products._valid_to, COALESCE(dim_components._valid_to, '2099-01-01')) AS _valid_to
    FROM join_products
    -- TODO: this might cause problems once we make these properly historical
    -- normally this would be an inner join
    LEFT JOIN dim_components
        ON join_products.component_key = dim_components.original_record_id
        AND join_products._valid_from < COALESCE(dim_components._valid_to, '2099-01-01')
        AND join_products._valid_to > COALESCE(dim_components._valid_from, '1900-01-01')
)

SELECT * FROM dim_service_components
