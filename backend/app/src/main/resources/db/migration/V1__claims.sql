-- The source of truth: everything that has happened to every claim, in order.
-- Rows are only ever inserted. The primary key is what makes two writers who
-- both built on the same version collide instead of both succeeding.
CREATE TABLE claim_events (
    claim_id    uuid        NOT NULL,
    version     integer     NOT NULL CHECK (version > 0),
    event_type  text        NOT NULL,
    payload     jsonb       NOT NULL,
    occurred_at timestamptz NOT NULL,
    PRIMARY KEY (claim_id, version)
);

-- One row per claim, for listing and filtering. A projection: it is written in
-- the same transaction as the events and could be rebuilt from them.
CREATE TABLE claim_summaries (
    claim_id       uuid        PRIMARY KEY,
    version        integer     NOT NULL,
    status         text        NOT NULL,
    submitted_at   timestamptz NOT NULL,
    departure_date date        NOT NULL,
    train_number   text        NOT NULL,
    total_ore      bigint
);

CREATE INDEX claim_summaries_by_status ON claim_summaries (status, submitted_at DESC);
