-- supabase/migration-series-status.sql
-- Run once in the Supabase SQL Editor.
--
-- Tracks the series' own publication status (ongoing/hiatus/finished/
-- cancelled), separate from list_status which tracks personal reading
-- progress. Sourced from AniList; only meaningful for manga/manhwa today.

alter table written_media add column series_status text;
