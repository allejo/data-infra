{{ config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by = {
            'field': 'dt',
            'data_type': 'date',
            'granularity': 'day',
        },
        cluster_by='group_id',
    )
}}

{% if is_incremental() %}
    {% set dates = dbt_utils.get_column_values(table=this, column='dt', order_by = 'dt DESC', max_records = 1) %}
    {% set max_dt = dates[0] %}
{% endif %}

WITH fct_rt_feed_fetch_errors AS (
    SELECT
        project_id,
        timestamp,
        event_id,
        platform,
        environment,
        release,
        dist,
        ip_address_v4,
        ip_address_v6,
        user,
        user_id,
        user_name,
        user_email,
        sdk_name,
        sdk_version,
        http_method,
        http_referer,
        tags_key,
        tags_value,
        contexts_key,
        contexts_value,
        transaction_name,
        span_id,
        trace_id,
        `partition`,
        offset,
        message_timestamp,
        retention_days,
        deleted,
        group_id,
        primary_hash,
        hierarchical_hashes,
        received,
        message,
        title,
        culprit,
        level,
        location,
        version,
        type,
        exception_stacks_type,
        exception_stacks_value,
        exception_stacks_mechanism_type,
        exception_stacks_mechanism_handled,
        exception_frames_abs_path,
        exception_frames_colno,
        exception_frames_filename,
        exception_frames_function,
        exception_frames_lineno,
        exception_frames_in_app,
        exception_frames_package,
        exception_frames_module,
        exception_frames_stack_level,
        sdk_integrations,
        modules_name,
        modules_version,
        project_slug,
        dt,
        execution_ts
    FROM {{ ref('stg_rt__feed_fetch_errors') }}
    WHERE message LIKE '%RTFetchException%'
    {% if is_incremental() %}
    AND dt >= '{{ max_dt }}'
    {% else %}
    AND dt >= DATE_SUB(CURRENT_DATE(), INTERVAL {{ var('RT_LOOKBACK_DAYS') }} DAY)
    {% endif %}
)

SELECT * FROM fct_rt_feed_fetch_errors
