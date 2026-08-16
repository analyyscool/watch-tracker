-- supabase/migration-together-tier-list.sql
-- Run once in the Supabase SQL Editor.
--
-- Backs Together-scope tier list / ranked list placement in Supabase
-- (shared, one tier per show) instead of per-browser localStorage — Karl's
-- and Liisa's personal-scope tier lists stay localStorage-only, unchanged.

alter table shows add column tier text;
alter table shows add column rank int;
