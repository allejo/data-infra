{{ config(materialized='table') }}

WITH int_gtfs_schedule__daily_scheduled_service_index AS (
    SELECT *
    FROM {{ ref('int_gtfs_schedule__daily_scheduled_service_index') }}
),

dim_trips AS (
    SELECT *
    FROM {{ ref('dim_trips') }}
),

dim_routes AS (
    SELECT *
    FROM {{ ref('dim_routes') }}
),

fct_daily_schedule_feeds AS (
    SELECT * FROM {{ ref('fct_daily_schedule_feeds') }}
),

dim_shapes_arrays AS (
    SELECT * FROM {{ ref('dim_shapes_arrays') }}
),

dim_gtfs_datasets AS (
    SELECT *
    FROM {{ ref('dim_gtfs_datasets') }}
),

stop_times_grouped AS (
    SELECT * FROM {{ ref('int_gtfs_schedule__stop_times_grouped') }}
),

gtfs_joins AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['service_index.service_date', 'trips.key', 'stop_times_grouped.iteration_num']) }} AS key,

        service_index.service_date,
        service_index.feed_key,
        trips.base64_url,
        service_index.service_id,
        service_index.feed_timezone,

        trips.key AS trip_key,
        trips.trip_id AS trip_id,
        trips.trip_short_name,
        trips.direction_id,
        trips.block_id,
        stop_times_grouped.iteration_num,
        stop_times_grouped.frequencies_defined_trip,

        routes.key AS route_key,
        routes.route_id AS route_id,
        routes.route_type,
        routes.route_short_name,
        routes.route_long_name,
        routes.route_desc,
        routes.agency_id AS agency_id,
        routes.network_id AS network_id,
        routes.continuous_pickup AS route_continuous_pickup,
        routes.continuous_drop_off AS route_continuous_drop_off,

        shapes.key AS shape_array_key,

        trips.shape_id,
        trips.warning_duplicate_gtfs_key AS contains_warning_duplicate_trip_primary_key,

        stop_times_grouped.num_distinct_stops_served,
        stop_times_grouped.num_stop_times,
        stop_times_grouped.trip_first_departure_sec,
        stop_times_grouped.trip_last_arrival_sec,
        stop_times_grouped.service_hours,
        stop_times_grouped.flex_service_hours,
        stop_times_grouped.contains_warning_duplicate_gtfs_key AS contains_warning_duplicate_stop_times_primary_key,
        stop_times_grouped.contains_warning_missing_foreign_key_stop_id,
        stop_times_grouped.trip_start_timezone,
        stop_times_grouped.trip_end_timezone,
        stop_times_grouped.is_gtfs_flex_trip,
        stop_times_grouped.num_gtfs_flex_stop_times,
        stop_times_grouped.is_entirely_demand_responsive_trip,
        stop_times_grouped.has_rider_service,
        stop_times_grouped.first_start_pickup_drop_off_window_sec,
        stop_times_grouped.last_end_pickup_drop_off_window_sec,
        stop_times_grouped.num_approximate_timepoint_stop_times,
        stop_times_grouped.num_exact_timepoint_stop_times,
        stop_times_grouped.num_arrival_times_populated_stop_times,
        stop_times_grouped.num_departure_times_populated_stop_times,
        -- spec is explicit: all stop times are relative to midnight in the feed time zone (from agency.txt)
        -- see: https://gtfs.org/schedule/reference/#stopstxt
        -- so to make a timestamp, we use the feed timezone from agency.txt
        TIMESTAMP_ADD(
            {{ gtfs_noon_minus_twelve_hours('service_date', 'service_index.feed_timezone') }},
            INTERVAL stop_times_grouped.trip_first_departure_sec SECOND
            ) AS trip_first_departure_ts,

        TIMESTAMP_ADD(
            {{ gtfs_noon_minus_twelve_hours('service_date', 'service_index.feed_timezone') }},
            INTERVAL stop_times_grouped.trip_last_arrival_sec SECOND
            ) AS trip_last_arrival_ts,

        TIMESTAMP_ADD(
            {{ gtfs_noon_minus_twelve_hours('service_date', 'service_index.feed_timezone') }},
            INTERVAL stop_times_grouped.first_start_pickup_drop_off_window_sec SECOND
            ) AS trip_first_start_pickup_drop_off_window_ts,

        TIMESTAMP_ADD(
            {{ gtfs_noon_minus_twelve_hours('service_date', 'service_index.feed_timezone') }},
            INTERVAL stop_times_grouped.last_end_pickup_drop_off_window_sec SECOND
            ) AS trip_last_end_pickup_drop_off_window_ts,

    FROM int_gtfs_schedule__daily_scheduled_service_index AS service_index
    INNER JOIN dim_trips AS trips
        ON service_index.feed_key = trips.feed_key
            AND service_index.service_id = trips.service_id
    LEFT JOIN dim_routes AS routes
        ON service_index.feed_key = routes.feed_key
            AND trips.route_id = routes.route_id
    LEFT JOIN dim_shapes_arrays AS shapes
        ON service_index.feed_key = shapes.feed_key
            AND trips.shape_id = shapes.shape_id
    LEFT JOIN stop_times_grouped
        ON service_index.feed_key = stop_times_grouped.feed_key
            AND trips.trip_id = stop_times_grouped.trip_id
    -- drop trips with no stops
    WHERE stop_times_grouped.feed_key IS NOT NULL
),

fct_daily_scheduled_trips AS (
    SELECT
        gtfs_joins.key,
        gtfs_joins.feed_timezone,
        gtfs_joins.base64_url,

        dim_gtfs_datasets.name,
        dim_gtfs_datasets.regional_feed_type,

        daily_feeds.gtfs_dataset_key AS gtfs_dataset_key,

        gtfs_joins.service_date,
        gtfs_joins.feed_key,
        gtfs_joins.service_id,
        gtfs_joins.trip_key,
        gtfs_joins.trip_id,
        gtfs_joins.iteration_num,
        gtfs_joins.frequencies_defined_trip,
        gtfs_joins.trip_short_name,
        gtfs_joins.direction_id,
        gtfs_joins.block_id,
        gtfs_joins.route_key,
        gtfs_joins.route_id,
        gtfs_joins.route_type,
        gtfs_joins.route_short_name,
        gtfs_joins.route_long_name,
        gtfs_joins.route_continuous_pickup,
        gtfs_joins.route_continuous_drop_off,
        gtfs_joins.route_desc,
        gtfs_joins.agency_id,
        gtfs_joins.network_id,
        gtfs_joins.shape_array_key,
        gtfs_joins.shape_id,
        gtfs_joins.contains_warning_duplicate_trip_primary_key,
        gtfs_joins.num_distinct_stops_served,
        gtfs_joins.num_stop_times,
        gtfs_joins.trip_first_departure_sec,
        gtfs_joins.trip_last_arrival_sec,
        gtfs_joins.trip_start_timezone,
        gtfs_joins.trip_end_timezone,
        gtfs_joins.service_hours,
        gtfs_joins.flex_service_hours,
        gtfs_joins.contains_warning_duplicate_stop_times_primary_key,
        gtfs_joins.contains_warning_missing_foreign_key_stop_id,
        gtfs_joins.trip_first_departure_ts,
        gtfs_joins.trip_last_arrival_ts,
        gtfs_joins.first_start_pickup_drop_off_window_sec,
        gtfs_joins.last_end_pickup_drop_off_window_sec,
        gtfs_joins.is_gtfs_flex_trip,
        gtfs_joins.is_entirely_demand_responsive_trip,
        gtfs_joins.num_gtfs_flex_stop_times,
        gtfs_joins.num_approximate_timepoint_stop_times,
        gtfs_joins.num_exact_timepoint_stop_times,
        gtfs_joins.num_arrival_times_populated_stop_times,
        gtfs_joins.num_departure_times_populated_stop_times,
        gtfs_joins.trip_first_start_pickup_drop_off_window_ts,
        gtfs_joins.trip_last_end_pickup_drop_off_window_ts,
        DATE(trip_first_departure_ts, "America/Los_Angeles") AS trip_start_date_pacific,
        DATETIME(trip_first_departure_ts, "America/Los_Angeles") AS trip_first_departure_datetime_pacific,
        DATETIME(trip_last_arrival_ts, "America/Los_Angeles") AS trip_last_arrival_datetime_pacific,
        DATE(trip_first_departure_ts, trip_start_timezone) AS trip_start_date_local_tz,
        DATETIME(trip_first_departure_ts, trip_start_timezone) AS trip_first_departure_datetime_local_tz,
        DATETIME(trip_last_arrival_ts, trip_end_timezone) AS trip_last_arrival_datetime_local_tz,
        DATE(trip_first_start_pickup_drop_off_window_ts, "America/Los_Angeles") AS trip_first_start_pickup_drop_off_window_date_pacific,
        DATETIME(trip_first_start_pickup_drop_off_window_ts, "America/Los_Angeles") AS trip_first_start_pickup_drop_off_window_datetime_pacific,
        DATETIME(trip_last_end_pickup_drop_off_window_ts, "America/Los_Angeles") AS trip_last_end_pickup_drop_off_window_pacific,
        DATE(trip_first_start_pickup_drop_off_window_ts, trip_start_timezone) AS trip_first_start_pickup_drop_off_window_date_local_tz,
        DATETIME(trip_first_start_pickup_drop_off_window_ts, trip_start_timezone) AS trip_first_start_pickup_drop_off_window_datetime_local_tz,
        DATETIME(trip_last_end_pickup_drop_off_window_ts, trip_end_timezone) AS trip_last_end_pickup_drop_off_window_datetime_local_tz,
    FROM gtfs_joins
    LEFT JOIN fct_daily_schedule_feeds AS daily_feeds
        ON gtfs_joins.feed_key = daily_feeds.feed_key
        AND gtfs_joins.service_date = daily_feeds.date
    LEFT JOIN dim_gtfs_datasets
        ON daily_feeds.gtfs_dataset_key = dim_gtfs_datasets.key
    -- drop trips that no one can actually ride
    WHERE has_rider_service
)

SELECT * FROM fct_daily_scheduled_trips
