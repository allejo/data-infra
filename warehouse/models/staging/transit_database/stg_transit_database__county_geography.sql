{{ config(materialized='table') }}

WITH
latest AS (
    {{ get_latest_external_data(
        external_table = source('airtable', 'california_transit__county_geography'),
        order_by = 'dt DESC, time DESC'
        ) }}
),

stg_transit_database__county_geography AS (
    SELECT
        county_geography_id AS key,
        {{ trim_make_empty_string_null(column_name = "name") }},
        fips,
        msa,
        caltrans_district,
        caltrans_district_name,
        unnested_rtpa AS rtpa,
        mpo,
        place_geography,
        time,
        dt AS calitp_extracted_at
    FROM latest
    LEFT JOIN UNNEST(latest.rtpa) AS unnested_rtpa
)

SELECT * FROM stg_transit_database__county_geography
