-- Track when each holding was first created so the dashboard can show
-- the propagation delay between order approval and portfolio update.
ALTER TABLE holding
    ADD COLUMN added_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
