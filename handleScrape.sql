\set bch_current `cat :bch_scrape_datadir/current.json`
\set bch_restored `cat :bch_scrape_datadir/restored.json`
\set bch_planned `cat :bch_scrape_datadir/planned.json`
SELECT bchydro.update_all_outages(
    :'bch_scrape_timestamp',
    :'bch_current',
    :'bch_restored',
    :'bch_planned',
    INTERVAL '30 MINUTES'
);
