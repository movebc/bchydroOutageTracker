CREATE SCHEMA IF NOT EXISTS bchydro;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE bchydro.outage_status AS ENUM ('PLANNED', 'CURRENT', 'RESTORED');

CREATE TABLE bchydro.outages (
    id TEXT NOT NULL PRIMARY KEY,
    was_planned BOOLEAN NOT NULL DEFAULT FALSE,
    stale_since timestamptz DEFAULT NULL
);

CREATE TABLE bchydro.outage_updates (
    id TEXT NOT NULL
        REFERENCES bchydro.outages (id)
        ON DELETE CASCADE,
    update_index INT NOT NULL
        DEFAULT 0
        CHECK ( update_index >= 0 ),
    first_scrape_ts timestamptz NOT NULL,
    last_scrape_ts timestamptz NOT NULL,
    data_period tstzrange NOT NULL
        GENERATED ALWAYS AS ( tstzrange(first_scrape_ts, last_scrape_ts, CASE WHEN first_scrape_ts = last_scrape_ts THEN '[]' ELSE '[)' END) ) STORED,
    bch_first_updated timestamptz NOT NULL,
    bch_last_updated timestamptz NOT NULL,
    bch_period tstzrange NOT NULL
        GENERATED ALWAYS AS ( tstzrange(bch_first_updated, bch_last_updated, CASE WHEN bch_first_updated = bch_last_updated THEN '[]' ELSE '[)' END) ) STORED,

    status bchydro.outage_status NOT NULL,
    analyzed_status TEXT,
    area TEXT,
    cause TEXT,
    crew_eta timestamptz,
    crew_etr timestamptz,
    crew_status TEXT,
    crew_status_descr TEXT,
    crew_status_note TEXT,
    date_off timestamptz NOT NULL,
    date_on timestamptz,
    gis_id TEXT,
    point geometry(POINT, 4326),
    polygon geometry(POLYGON, 4326),
    municipality TEXT,
    num_customers_out INT NOT NULL,
    region_id TEXT NOT NULL,
    region_name TEXT NOT NULL,
    show_date_on BOOLEAN NOT NULL,
    show_eta BOOLEAN NOT NULL,
    show_etr BOOLEAN NOT NULL,

    CONSTRAINT outage_updates_scrape_ts_ordering CHECK ( first_scrape_ts <= last_scrape_ts ),
    CONSTRAINT outage_updates_bch_ts_ordering CHECK ( bch_first_updated <= bch_last_updated ),
    PRIMARY KEY (id, update_index),
    UNIQUE (id, data_period WITHOUT OVERLAPS)
);
CREATE INDEX outage_updates_id_index ON bchydro.outage_updates (id);
CREATE INDEX outage_updates_point_index ON bchydro.outage_updates USING gist (point);
CREATE INDEX outage_updates_polygon_index ON bchydro.outage_updates USING gist (polygon);

CREATE MATERIALIZED VIEW bchydro.current_outage_status AS
WITH outage_aggregate AS (
    SELECT
        id,
        max(update_index) AS most_recent_update_index,
        min(first_scrape_ts) AS outage_first_scrape_ts,
        max(last_scrape_ts) AS outage_last_scrape_ts,
        range_merge(range_agg(data_period)) AS outage_data_period,
        min(bch_first_updated) AS outage_bch_first_updated,
        max(bch_last_updated) AS outage_bch_last_updated,
        range_merge(range_agg(bch_period)) AS outage_bch_period
    FROM bchydro.outages o
    JOIN bchydro.outage_updates u USING (id)
    GROUP BY id
)
SELECT DISTINCT
    id,
    was_planned,
    stale_since,

    most_recent_update_index,
    outage_first_scrape_ts,
    outage_last_scrape_ts,
    outage_data_period,
    outage_bch_first_updated,
    outage_bch_last_updated,
    outage_bch_period,

    first_value(update_index) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_update_index,
    first_value(first_scrape_ts) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_first_scrape_ts,
    first_value(last_scrape_ts) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_last_scrape_ts,
    first_value(data_period) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_data_period,
    first_value(bch_first_updated) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_bch_first_updated,
    first_value(bch_last_updated) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_bch_last_updated,
    first_value(bch_period) OVER (PARTITION BY id ORDER BY update_index DESC) AS this_scrape_bch_period,

    first_value(status) OVER (PARTITION BY id ORDER BY CASE WHEN status IS NULL THEN -1 ELSE update_index END DESC) AS status,
    first_value(analyzed_status) OVER (PARTITION BY id ORDER BY CASE WHEN analyzed_status IS NULL THEN -1 ELSE update_index END DESC) AS analyzed_status,
    first_value(area) OVER (PARTITION BY id ORDER BY CASE WHEN area IS NULL THEN -1 ELSE update_index END DESC) AS area,
    first_value(cause) OVER (PARTITION BY id ORDER BY CASE WHEN cause IS NULL THEN -1 ELSE update_index END DESC) AS cause,
    first_value(crew_eta) OVER (PARTITION BY id ORDER BY CASE WHEN crew_eta IS NULL THEN -1 ELSE update_index END DESC) AS crew_eta,
    first_value(crew_etr) OVER (PARTITION BY id ORDER BY CASE WHEN crew_etr IS NULL THEN -1 ELSE update_index END DESC) AS crew_etr,
    first_value(crew_status) OVER (PARTITION BY id ORDER BY CASE WHEN crew_status IS NULL THEN -1 ELSE update_index END DESC) AS crew_status,
    first_value(crew_status_descr) OVER (PARTITION BY id ORDER BY CASE WHEN crew_status_descr IS NULL THEN -1 ELSE update_index END DESC) AS crew_status_descr,
    first_value(crew_status_note) OVER (PARTITION BY id ORDER BY CASE WHEN crew_status_note IS NULL THEN -1 ELSE update_index END DESC) AS crew_status_note,
    first_value(date_off) OVER (PARTITION BY id ORDER BY CASE WHEN date_off IS NULL THEN -1 ELSE update_index END DESC) AS date_off,
    first_value(date_on) OVER (PARTITION BY id ORDER BY CASE WHEN date_on IS NULL THEN -1 ELSE update_index END DESC) AS date_on,
    first_value(gis_id) OVER (PARTITION BY id ORDER BY CASE WHEN gis_id IS NULL THEN -1 ELSE update_index END DESC) AS gis_id,
    first_value(point) OVER (PARTITION BY id ORDER BY CASE WHEN point IS NULL THEN -1 ELSE update_index END DESC) AS point,
    first_value(polygon) OVER (PARTITION BY id ORDER BY CASE WHEN polygon IS NULL THEN -1 ELSE update_index END DESC) AS polygon,
    first_value(municipality) OVER (PARTITION BY id ORDER BY CASE WHEN municipality IS NULL THEN -1 ELSE update_index END DESC) AS municipality,
    first_value(num_customers_out) OVER (PARTITION BY id ORDER BY CASE WHEN num_customers_out IS NULL THEN -1 ELSE update_index END DESC) AS num_customers_out,
    first_value(region_id) OVER (PARTITION BY id ORDER BY CASE WHEN region_id IS NULL THEN -1 ELSE update_index END DESC) AS region_id,
    first_value(region_name) OVER (PARTITION BY id ORDER BY CASE WHEN region_name IS NULL THEN -1 ELSE update_index END DESC) AS region_name,
    first_value(show_date_on) OVER (PARTITION BY id ORDER BY CASE WHEN show_date_on IS NULL THEN -1 ELSE update_index END DESC) AS show_date_on,
    first_value(show_eta) OVER (PARTITION BY id ORDER BY CASE WHEN show_eta IS NULL THEN -1 ELSE update_index END DESC) AS show_eta,
    first_value(show_etr) OVER (PARTITION BY id ORDER BY CASE WHEN show_etr IS NULL THEN -1 ELSE update_index END DESC) AS show_etr
FROM bchydro.outages o
JOIN bchydro.outage_updates u USING (id)
JOIN outage_aggregate a USING (id);
CREATE UNIQUE INDEX current_outage_status_id_index ON bchydro.current_outage_status (id);
CREATE INDEX current_outage_status_point_index ON bchydro.current_outage_status USING gist (point);
CREATE INDEX current_outage_status_polygon_index ON bchydro.current_outage_status USING gist (polygon);

CREATE FUNCTION bchydro.number_array_to_polygon(raw DOUBLE PRECISION[])
RETURNS geometry(POLYGON, 4326)
RETURNS NULL ON NULL INPUT
IMMUTABLE
AS $$
WITH lagged AS (
    SELECT
        v AS y,
        lead(v) OVER (ORDER BY i) AS x,
        i
    FROM LATERAL unnest(raw) WITH ORDINALITY u(v, i)
), points AS (
    SELECT
        st_setsrid(st_makepoint(y, x), 4326) AS geom, i
    FROM lagged
    WHERE i % 2 = 1
), line AS (
    SELECT
        st_makeline(geom) AS geom
    FROM points
)
SELECT
    CASE WHEN st_startpoint(geom) != st_endpoint(geom) THEN
    st_makepolygon(st_addpoint(geom, st_startpoint(geom)))
    ELSE st_makepolygon(geom) END AS geom
FROM line
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION bchydro.update_outage(
    scrape_status bchydro.outage_status,
    scrape_time timestamptz,
    new_id TEXT,
    new_analyzed_status TEXT,
    new_area TEXT,
    new_cause TEXT,
    new_crew_eta timestamptz,
    new_crew_etr timestamptz,
    new_crew_status TEXT,
    new_crew_status_descr TEXT,
    new_crew_status_note TEXT,
    new_date_off timestamptz,
    new_date_on timestamptz,
    new_gis_id TEXT,
    new_last_updated timestamptz,
    new_point geometry(POINT, 4326),
    new_municipality TEXT,
    new_num_customers_out INT,
    new_polygon geometry(POLYGON, 4326),
    new_region_id TEXT,
    new_region_name TEXT,
    new_show_date_on BOOLEAN,
    new_show_eta BOOLEAN,
    new_show_etr BOOLEAN
)
RETURNS VOID
AS $$
    DECLARE
        last_update bchydro.outage_updates;
    BEGIN
        INSERT INTO bchydro.outages (id, was_planned, stale_since)
        VALUES (new_id, scrape_status = 'PLANNED', NULL)
        ON CONFLICT (id) DO UPDATE SET stale_since = NULL;
        
        SELECT * FROM bchydro.outage_updates
        WHERE id = new_id
        ORDER BY update_index DESC
        LIMIT 1
        INTO last_update;
        
        IF (last_update).id IS NULL THEN
            INSERT INTO bchydro.outage_updates (
                status, id, update_index, first_scrape_ts, last_scrape_ts, bch_first_updated,
                bch_last_updated, analyzed_status, area, cause, crew_eta, crew_etr, crew_status, crew_status_descr,
                crew_status_note, date_off, date_on, gis_id, point, polygon, municipality, num_customers_out,
                region_id, region_name, show_date_on, show_eta, show_etr
            ) VALUES (
                scrape_status, new_id, 0,
                scrape_time, scrape_time,
                new_last_updated, new_last_updated,
                new_analyzed_status, new_area, new_cause, new_crew_eta,
                new_crew_etr, new_crew_status, new_crew_status_descr,
                new_crew_status_note, new_date_off, new_date_on, new_gis_id,
                new_point, new_polygon, new_municipality, new_num_customers_out,
                new_region_id, new_region_name, new_show_date_on, new_show_eta, new_show_etr
            );
        ELSE
            UPDATE bchydro.outage_updates SET
                last_scrape_ts = scrape_time,
                bch_last_updated = new_last_updated
            WHERE id = new_id AND update_index = (last_update).update_index;
            IF
                (last_update).status != scrape_status OR
                (last_update).analyzed_status != new_analyzed_status OR
                (last_update).area != new_area OR
                (last_update).cause != new_cause OR
                (last_update).crew_eta != new_crew_eta OR
                (last_update).crew_etr != new_crew_etr OR
                (last_update).crew_status != new_crew_status OR
                (last_update).crew_status_descr != new_crew_status_descr OR
                (last_update).crew_status_descr != new_crew_status_descr OR
                (last_update).crew_status_note != new_crew_status_note OR
                (last_update).date_off != new_date_off OR
                (last_update).date_on != new_date_on OR
                (last_update).gis_id != new_gis_id OR
                (last_update).point != new_point OR
                (last_update).polygon != new_polygon OR
                (last_update).municipality != new_municipality OR
                (last_update).num_customers_out != new_num_customers_out OR
                (last_update).region_id != new_region_id OR
                (last_update).region_name != new_region_name OR
                (last_update).show_date_on != new_show_date_on OR
                (last_update).show_eta != new_show_eta OR
                (last_update).show_etr != new_show_etr
            THEN -- something's changed, update needed
                UPDATE bchydro.outage_updates
                SET last_scrape_ts = scrape_time, bch_last_updated = new_last_updated
                WHERE id = new_id AND update_index = (last_update).update_index;

                INSERT INTO bchydro.outage_updates (
                    status, id, update_index, first_scrape_ts, last_scrape_ts, bch_first_updated,
                    bch_last_updated, analyzed_status, area, cause, crew_eta, crew_etr, crew_status, crew_status_descr,
                    crew_status_note, date_off, date_on, gis_id, point, polygon, municipality, num_customers_out,
                    region_id, region_name, show_date_on, show_eta, show_etr
                ) VALUES (
                    scrape_status, new_id, (last_update).update_index + 1,
                    scrape_time, scrape_time,
                    new_last_updated, new_last_updated, new_analyzed_status,
                    new_area, new_cause, new_crew_eta, new_crew_etr, new_crew_status,
                    new_crew_status_descr, new_crew_status_note, new_date_off, new_date_on,
                    new_gis_id, new_point, new_polygon, new_municipality, new_num_customers_out,
                    new_region_id, new_region_name, new_show_date_on, new_show_eta, new_show_etr
                );
            END IF;
        END IF;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bchydro.update_outages(scrape_status bchydro.outage_status, scrape_time timestamptz, raw_data jsonb)
RETURNS VOID
AS $$
DECLARE
    outage_json jsonb;
BEGIN
    FOR outage_json IN SELECT jsonb_array_elements(jsonb_array_elements(raw_data -> 'regions') -> 'outages') LOOP
        BEGIN
            PERFORM bchydro.update_outage(
                scrape_status,
                scrape_time,
                "id",
                nullif("analyzedStatus", ''),
                nullif("area", ''),
                nullif("cause", ''),
                to_timestamp("crewEta" / 1000),
                to_timestamp("crewEtr" / 1000),
                nullif("crewStatus", ''),
                nullif("crewStatusDescr", ''),
                nullif("crewStatusNote", ''),
                to_timestamp("dateOff" / 1000),
                to_timestamp("dateOn" / 1000),
                nullif("gisId", ''),
                to_timestamp("lastUpdated" / 1000),
                CASE
                    WHEN latitude IS NOT NULL AND latitude != 0 AND longitude IS NOT NULL AND longitude != 0
                    THEN st_setsrid(st_makepoint(longitude, latitude), 4326)
                END,
                nullif("municipality", ''),
                "numCustomersOut",
                bchydro.number_array_to_polygon(nullif("polygon", ARRAY []::DOUBLE PRECISION[])),
                "regionId",
                "regionName",
                "showDateOn",
                "showEta",
                "showEtr"
            )
            FROM jsonb_to_record(outage_json) AS parsed (
                "id" TEXT,
                "analyzedStatus" TEXT,
                "area" TEXT,
                "cause" TEXT,
                "crewEta" INT8,
                "crewEtr" INT8,
                "crewStatus" TEXT,
                "crewStatusDescr" TEXT,
                "crewStatusNote" TEXT,
                "dateOff" INT8,
                "dateOn" INT8,
                "gisId" TEXT,
                "lastUpdated" INT8,
                "latitude" DOUBLE PRECISION,
                "longitude" DOUBLE PRECISION,
                "municipalities" TEXT[],
                "municipality" TEXT,
                "numCustomersOut" INT,
                "polygon" DOUBLE PRECISION[],
                "regionId" TEXT,
                "regionName" TEXT,
                "showDateOn" BOOLEAN,
                "showEta" BOOLEAN,
                "showEtr" BOOLEAN
            );
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bchydro.post_scrape_housekeeping(scrape_time timestamptz, stale_threshold interval)
RETURNS VOID
AS $$
    BEGIN
        WITH last_updated AS (
            SELECT
                id, max(last_scrape_ts) AS last_scrape_ts
            FROM bchydro.outages
            JOIN bchydro.outage_updates USING (id)
            WHERE stale_since IS NULL
            GROUP BY id
        )
        UPDATE bchydro.outages o SET stale_since = scrape_time
        FROM last_updated lu
        WHERE o.id = lu.id AND (last_scrape_ts + stale_threshold) < scrape_time;

        REFRESH MATERIALIZED VIEW bchydro.current_outage_status;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bchydro.update_all_outages(scrape_time timestamptz, current jsonb, restored jsonb, planned jsonb, stale_threshold interval)
RETURNS VOID
AS $$
    SELECT
        bchydro.update_outages('CURRENT', scrape_time, current),
        bchydro.update_outages('RESTORED', scrape_time, restored),
        bchydro.update_outages('PLANNED', scrape_time, planned);
    SELECT bchydro.post_scrape_housekeeping(scrape_time, stale_threshold);
$$ LANGUAGE sql;
