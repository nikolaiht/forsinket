-- When the demo last started over from its seed data. A timer inside the
-- service is not enough to know that: a host that stops the service between
-- visits also stops the timer, and a service that has just started has to be
-- able to see whether it is time again. Holds at most one row, and is only
-- touched when the service runs as a demo.
CREATE TABLE demo_resets (
    reset_at timestamptz NOT NULL
);
