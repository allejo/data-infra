WITH dim_routes AS (
    SELECT  * FROM {{ ref('dim_routes') }}
),

feed_version_history AS (
    SELECT * FROM {{ ref('int_gtfs_quality__feed_version_history') }}
),

route_id_comparison AS (
    SELECT * FROM {{ ids_version_compare_aggregate("route_id","dim_routes") }}
),

table_partial AS (

    SELECT
        *,
        CASE
            WHEN id IS NULL AND prev_id IS NOT NULL THEN 'Removed'
            WHEN prev_id IS NULL AND id IS NOT NULL THEN 'Added'
            ELSE 'Unchanged'
        END AS change_status
    FROM route_id_comparison
    --FULL JOIN table_end AS t2
                --USING ( calitp_itp_id, calitp_url_number, metric_period, metric_date, source_id)

),

metric_counts AS (

    SELECT
        base64_url,
        feed_key,
        change_status,
        COUNT(*) AS n
    FROM table_partial GROUP BY 1, 2, 3

),

fct_monthly_route_id_changes AS (

    SELECT * FROM metric_counts

)

SELECT * FROM fct_monthly_route_id_changes
