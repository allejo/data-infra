{{ config(materialized='table') }}

WITH dim AS (
    SELECT *
    FROM {{ ref('int_transit_database__organizations_dim') }}
),

dim_organizations AS (
    SELECT
        key,
        name,
        organization_type,
        roles,
        itp_id,
        details,
        caltrans_district,
        website,
        reporting_category,
        ntd_agency_info_key,
        hubspot_company_record_id,
        gtfs_static_status,
        gtfs_realtime_status,
        assessment_status,
        alias,
        _is_current,
        _valid_from,
        _valid_to
    FROM dim
)

SELECT * FROM dim_organizations
