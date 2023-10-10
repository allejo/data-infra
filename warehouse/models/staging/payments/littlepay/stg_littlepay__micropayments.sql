WITH source AS (
    SELECT * FROM {{ source('external_littlepay', 'micropayments') }}
),

clean_columns AS (
    SELECT
        {{ trim_make_empty_string_null('micropayment_id') }} AS micropayment_id,
        {{ trim_make_empty_string_null('aggregation_id') }} AS aggregation_id,
        {{ trim_make_empty_string_null('participant_id') }} AS participant_id,
        {{ trim_make_empty_string_null('customer_id') }} AS customer_id,
        {{ trim_make_empty_string_null('funding_source_vault_id') }} AS funding_source_vault_id,
        TIMESTAMP({{ trim_make_empty_string_null('transaction_time') }}) AS transaction_time,
        {{ trim_make_empty_string_null('payment_liability') }} AS payment_liability,
        SAFE_CAST(charge_amount AS NUMERIC) AS charge_amount,
        SAFE_CAST(nominal_amount AS NUMERIC) AS nominal_amount,
        {{ trim_make_empty_string_null('currency_code') }} AS currency_code,
        {{ trim_make_empty_string_null('type') }} AS type,
        {{ trim_make_empty_string_null('charge_type') }} AS charge_type,
        CAST(_line_number AS INTEGER) AS _line_number,
        `instance`,
        extract_filename,
        ts,
        {{ extract_littlepay_filename_ts() }} AS littlepay_export_ts,
        {{ extract_littlepay_filename_date() }} AS littlepay_export_date,
        -- hash all content not generated by us to enable deduping full dup rows
        -- hashing at this step will preserve distinction between nulls and empty strings in case that is meaningful upstream
        {{ dbt_utils.generate_surrogate_key(['participant_id',
            'aggregation_id', 'micropayment_id', 'customer_id', 'funding_source_vault_id', 'transaction_time',
            'payment_liability', 'charge_amount', 'nominal_amount',
            'currency_code', 'type', 'charge_type']) }} AS _content_hash,
    FROM source
),

dedupe_rows AS (
    SELECT *
    FROM clean_columns
    {{ qualify_dedupe_full_duplicate_lp_rows() }}
),

stg_littlepay__micropayments AS (
    SELECT
        micropayment_id,
        aggregation_id,
        participant_id,
        customer_id,
        funding_source_vault_id,
        transaction_time,
        payment_liability,
        charge_amount,
        nominal_amount,
        currency_code,
        type,
        charge_type,
        _line_number,
        `instance`,
        extract_filename,
        ts,
        littlepay_export_ts,
        littlepay_export_date,
        _content_hash,
        -- generate keys now that input columns have been trimmed & cast
        {{ dbt_utils.generate_surrogate_key(['littlepay_export_ts', '_line_number', 'instance']) }} AS _key,
        {{ dbt_utils.generate_surrogate_key(['micropayment_id']) }} AS _payments_key,
    FROM dedupe_rows
    -- completed variable fare payments have two rows with same micropayment id and different transaction times
    -- we keep the second tap for these
    QUALIFY ROW_NUMBER() OVER (PARTITION BY micropayment_id ORDER BY transaction_time DESC) = 1
)

SELECT * FROM stg_littlepay__micropayments
