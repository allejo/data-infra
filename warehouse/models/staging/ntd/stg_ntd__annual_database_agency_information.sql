WITH source AS (
    SELECT * FROM {{ source('ntd_data_products', 'annual_database_agency_information') }}
),

stg_ntd__annual_database_agency_information AS (
    SELECT
        number_of_state_counties,
        tam_tier,
        personal_vehicles,
        density,
        uza_name,
        tribal_area_name,
        service_area_sq_miles,
        total_voms,
        city,
        fta_recipient_id,
        region,
        state_admin_funds_expended,
        zip_code_ext,
        zip_code,
        ueid,
        address_line_2,
        number_of_counties_with_service,
        reporter_acronym,
        original_due_date,
        sq_miles,
        address_line_1,
        p_o__box,
        fy_end_date,
        reported_by_ntd_id,
        population,
        reporting_module,
        service_area_pop,
        subrecipient_type,
        state,
        volunteer_drivers,
        primary_uza,
        doing_business_as,
        reporter_type,
        legacy_ntd_id,
        voms_do,
        url,
        reported_by_name,
        voms_pt,
        organization_type,
        agency_name,
        ntd_id,
        dt,
        ts,
        year,
    FROM source
)

SELECT * FROM stg_ntd__annual_database_agency_information
