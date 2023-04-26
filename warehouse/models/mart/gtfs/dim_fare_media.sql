WITH make_dim AS (
    {{ make_schedule_file_dimension_from_dim_schedule_feeds(
        ref('dim_schedule_feeds'),
        ref('stg_gtfs_schedule__fare_media'),
    ) }}
),

dim_fare_media AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['feed_key', 'fare_media_id']) }} AS key,
        feed_key,
        base64_url,
        fare_media_id,
        fare_media_name,
        fare_media_type,
        _feed_valid_from,
        feed_timezone,
    FROM make_dim
)

SELECT * FROM dim_fare_media
