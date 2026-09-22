-- Pantheon backend, phase 1 (2026-09-22; Docs/BACKEND.md): players and
-- their cloud saves. Run once in the project's SQL editor (Dashboard →
-- SQL Editor → New query → paste → Run), or with `supabase db push`.
--
-- Every row is guarded by row-level security: a signed-in user (anonymous
-- for a guest, Apple for an Apple ID) reads and writes his own row and
-- nobody else's. The anon key the app carries can do nothing these
-- policies do not allow.

-- ---------------------------------------------------------------------
-- players: who each auth user is in the game's terms.
-- ---------------------------------------------------------------------
create table if not exists public.players (
    id            uuid primary key references auth.users (id) on delete cascade,
    provider      text not null default 'guest' check (provider in ('guest', 'apple')),
    display_name  text,
    -- The six characters the Account panel prints as "Player ID": how a
    -- support request finds the row.
    player_code   text not null,
    created_at    timestamptz not null default now(),
    last_seen_at  timestamptz not null default now()
);

create index if not exists players_player_code_idx on public.players (player_code);

alter table public.players enable row level security;

drop policy if exists "players: own row read"   on public.players;
drop policy if exists "players: own row insert" on public.players;
drop policy if exists "players: own row update" on public.players;

create policy "players: own row read"   on public.players for select to authenticated using (auth.uid() = id);
create policy "players: own row insert" on public.players for insert to authenticated with check (auth.uid() = id);
create policy "players: own row update" on public.players for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- ---------------------------------------------------------------------
-- saves: one row per player, the save as the exact JSON the phone wrote.
-- ---------------------------------------------------------------------
create table if not exists public.saves (
    player_id   uuid primary key references public.players (id) on delete cascade,
    -- The save file's bytes as text: it round-trips byte for byte, and a
    -- veteran's save passes the size a jsonb column is comfortable with.
    payload     text not null,
    version     integer not null default 1,
    -- The player's createdAt: two saves of one lineage are the same game on
    -- two phones; two lineages are two games, and the guard below never
    -- lets one overwrite the other.
    lineage     timestamptz not null,
    -- The save's own savedAt: the clock every comparison uses.
    saved_at    timestamptz not null,
    bytes       integer not null default 0,
    revision    integer not null default 1,
    updated_at  timestamptz not null default now()
);

alter table public.saves enable row level security;

drop policy if exists "saves: own row read"   on public.saves;
drop policy if exists "saves: own row insert" on public.saves;
drop policy if exists "saves: own row update" on public.saves;
drop policy if exists "saves: own row delete" on public.saves;

create policy "saves: own row read"   on public.saves for select to authenticated using (auth.uid() = player_id);
create policy "saves: own row insert" on public.saves for insert to authenticated with check (auth.uid() = player_id);
create policy "saves: own row update" on public.saves for update to authenticated using (auth.uid() = player_id) with check (auth.uid() = player_id);
create policy "saves: own row delete" on public.saves for delete to authenticated using (auth.uid() = player_id);

-- The rules CloudSaveStore enforced on the phone, enforced here as well,
-- so no client — not even a modified one — can bury a newer save or
-- another game's. The app reads the raised message: `lineage` means the
-- row is another game's (offered as "Restore from Pantheon Cloud"),
-- `stale` means another phone saved since (the upload is skipped).
create or replace function public.guard_save()
returns trigger
language plpgsql
as $$
begin
    if abs(extract(epoch from (new.lineage - old.lineage))) > 1 then
        raise exception 'lineage' using errcode = 'P0001';
    end if;
    if new.saved_at < old.saved_at - interval '1 second' then
        raise exception 'stale' using errcode = 'P0001';
    end if;
    new.revision := old.revision + 1;
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists saves_guard on public.saves;
create trigger saves_guard
    before update on public.saves
    for each row execute function public.guard_save();

-- The anon role sees nothing; only a signed-in user reaches the tables,
-- and only through the policies above.
revoke all on public.players from anon;
revoke all on public.saves   from anon;
grant select, insert, update         on public.players to authenticated;
grant select, insert, update, delete on public.saves   to authenticated;
