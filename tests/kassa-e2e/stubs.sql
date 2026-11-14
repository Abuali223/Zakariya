-- Supabase'ning auth/storage sxemalari faqat asosiy bazada bor; vaqtinchalik bazaga minimal o'rinbosarlar.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;   -- Supabase kabi (public'ga emas)
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, phone text, raw_user_meta_data jsonb, created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
