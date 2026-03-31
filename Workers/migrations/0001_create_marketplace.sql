-- Marketplace actions table for sharing translation action templates
CREATE TABLE IF NOT EXISTS marketplace_actions (
    id                 TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    name               TEXT NOT NULL,
    prompt             TEXT NOT NULL,
    action_description TEXT NOT NULL DEFAULT '',
    output_type        TEXT NOT NULL DEFAULT 'plain',
    usage_scenes       INTEGER NOT NULL DEFAULT 7,
    category           TEXT NOT NULL DEFAULT 'other',
    author_name        TEXT NOT NULL DEFAULT 'Anonymous',
    download_count     INTEGER NOT NULL DEFAULT 0,
    created_at         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    creator_id         TEXT
);

CREATE INDEX idx_marketplace_category ON marketplace_actions(category);
CREATE INDEX idx_marketplace_created_at ON marketplace_actions(created_at DESC);
CREATE INDEX idx_marketplace_download_count ON marketplace_actions(download_count DESC);
