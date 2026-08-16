-- supabase/migration-anime-synced-chapter.sql
-- Run once in the Supabase SQL Editor.
--
-- Marks written_media rows whose current_chapter was seeded from where the
-- anime adaptation currently ends, not from chapters actually read, so the
-- UI can flag it instead of it being misread as real reading progress.

alter table written_media add column chapter_synced_from_anime boolean not null default false;
