-- Pantheon backend, anonymous play data (2026-09-23; Docs/ANALYTICS.md).
-- Run once in the project's SQL editor (Dashboard → SQL Editor → New
-- query → paste → Run), or with `supabase db push`, after the two
-- migrations before it. Re-running it is safe: every statement is
-- `if not exists`, `create or replace` or `drop … if exists`.
--
-- One table the phones add rows to and never read back, and six views only
-- the dashboard reads. A row names no player: a random number the phone
-- made for its install (never the account, never Apple's id, never the
-- Player ID), an event name from the game's closed list, a few numbers and
-- game ids, the app version and the time. The phone sends with the anon key
-- alone, never a player's sign-in, so no request carries an event and an
-- account together — and there is no column for either, nor for an IP
-- address.

-- ---------------------------------------------------------------------
-- The schema only the dashboard reads. Supabase's Data API serves
-- `public` (and `graphql_public`); nothing in `analytics` is reachable
-- with the anon key, and the grants say so again.
-- ---------------------------------------------------------------------
create schema if not exists analytics;
revoke all on schema analytics from public;
revoke all on schema analytics from anon, authenticated;
comment on schema analytics is
    'Pantheon''s anonymous play data, read in the dashboard (Docs/ANALYTICS.md).';

-- ---------------------------------------------------------------------
-- events: one row per thing that happened in play.
-- ---------------------------------------------------------------------
create table if not exists public.events (
    id           bigint generated always as identity primary key,
    -- The random number the phone made for this install: made again when
    -- the player turns sharing off and on, and every thirteen months.
    install_id   uuid        not null,
    -- From the game's closed list (AnalyticsEventName in the app).
    name         text        not null check (name ~ '^[a-z][a-z0-9_]{1,31}$'),
    -- Numbers and game-id tokens only: the trigger below strips anything else.
    props        jsonb       not null default '{}'::jsonb
                             check (jsonb_typeof(props) = 'object' and octet_length(props::text) <= 1024),
    app_version  text        not null check (app_version ~ '^[0-9A-Za-z.+_-]{1,32}$'),
    -- `debug` from a build run out of Xcode; the views read `release` only.
    channel      text        not null default 'release' check (channel in ('release', 'debug')),
    -- The phone's clock, kept unless it is out by more than the trigger allows.
    occurred_at  timestamptz not null,
    -- The server's clock at arrival: what the daily cap counts.
    created_at   timestamptz not null default now()
);

comment on table public.events is
    'Anonymous play data: insert-only for the app, read through the analytics views (Docs/ANALYTICS.md).';

create index if not exists events_name_time_idx    on public.events (name, occurred_at);
create index if not exists events_install_time_idx on public.events (install_id, created_at);

-- Add, never read, change or remove: RLS allows an insert and nothing else,
-- and the grants are INSERT alone, on the six columns the phone sends (the
-- id and the arrival time are the server's). With `Prefer: return=minimal`
-- the insert reads nothing back, so no select policy is needed.
alter table public.events enable row level security;

drop policy if exists "events: anyone may add" on public.events;
create policy "events: anyone may add" on public.events
    for insert to anon, authenticated
    with check (true);

revoke all on public.events from anon, authenticated;
grant insert (install_id, name, props, app_version, channel, occurred_at)
    on public.events to anon, authenticated;

-- ---------------------------------------------------------------------
-- What the server keeps of a row, whatever a phone sent.
-- ---------------------------------------------------------------------
create or replace function analytics.accept_event()
returns trigger
language plpgsql
-- Runs as its owner so it may count the install's rows today, which the
-- inserting role may not read; hence the empty search_path.
security definer
set search_path = ''
as $$
declare
    today_count integer;
begin
    -- The phone's clock stands unless it is five minutes ahead or a week
    -- behind; then the arrival is the better guess.
    if new.occurred_at is null
       or new.occurred_at > now() + interval '5 minutes'
       or new.occurred_at < now() - interval '7 days' then
        new.occurred_at := now();
    end if;

    -- No free text, even from a modified phone: a key is lowercase, a value
    -- a number or a token of lowercase letters, digits and underscores (a
    -- stage's id, a step's name). Anything else is dropped from the row.
    if new.props is null or jsonb_typeof(new.props) <> 'object' then
        new.props := '{}'::jsonb;
    end if;
    new.props := coalesce((
        select jsonb_object_agg(p.key, p.value)
        from jsonb_each(new.props) as p (key, value)
        where p.key ~ '^[a-z][a-z0-9_]{0,23}$'
          and (jsonb_typeof(p.value) = 'number'
               or (jsonb_typeof(p.value) = 'string' and (p.value #>> '{}') ~ '^[a-z0-9_]{1,40}$'))
    ), '{}'::jsonb);

    -- The daily cap: 500 rows an install a UTC day (the phone stops itself
    -- at 400). Past it a row is dropped quietly rather than failing its batch.
    select count(*) into today_count
    from public.events e
    where e.install_id = new.install_id
      and e.created_at >= date_trunc('day', now(), 'UTC');
    if today_count >= 500 then
        return null;
    end if;
    return new;
end;
$$;

revoke all on function analytics.accept_event() from public;

drop trigger if exists events_accept on public.events;
create trigger events_accept
    before insert on public.events
    for each row execute function analytics.accept_event();

-- ---------------------------------------------------------------------
-- A property as a number or as text, or null when the row holds anything
-- else, so one odd row can never break a view's arithmetic. No SET clause:
-- Postgres inlines a plain SQL function like these into the views, and a
-- SET would stop it (the advisor's "search path mutable" warning on these
-- two is expected).
-- ---------------------------------------------------------------------
create or replace function analytics.num(p jsonb, k text)
returns numeric
language sql
immutable
as $$
    select case when jsonb_typeof(p -> k) = 'number' then (p ->> k)::numeric end
$$;

create or replace function analytics.txt(p jsonb, k text)
returns text
language sql
immutable
as $$
    select case when jsonb_typeof(p -> k) = 'string' then p ->> k end
$$;

-- ---------------------------------------------------------------------
-- The views (Docs/ANALYTICS.md §5 says what each answers). Read them in
-- the dashboard: SQL Editor → `select * from analytics.daily;`, or Table
-- Editor → the schema menu → analytics. Release builds only.
-- ---------------------------------------------------------------------

-- Each UTC day: who played, who arrived, how long they stayed, and how much
-- they fought and summoned.
create or replace view analytics.daily as
select
    (e.occurred_at at time zone 'UTC')::date                                 as day,
    count(distinct e.install_id)                                             as active_installs,
    count(*) filter (where e.name = 'first_open')                            as new_installs,
    count(*) filter (where e.name = 'session_start')                         as sessions,
    round(count(*) filter (where e.name = 'session_start')::numeric
          / nullif(count(distinct e.install_id), 0), 2)                      as sessions_per_install,
    round((percentile_cont(0.5) within group (order by analytics.num(e.props, 'seconds'))
           filter (where e.name = 'session_end'))::numeric / 60, 1)          as median_session_minutes,
    round(coalesce(sum(analytics.num(e.props, 'seconds')) filter (where e.name = 'session_end'), 0)
          / 60 / nullif(count(distinct e.install_id), 0), 1)                 as minutes_per_install,
    count(*) filter (where e.name = 'stage_result')                          as fights,
    coalesce(sum(analytics.num(e.props, 'count')) filter (where e.name = 'summon'), 0) as summons
from public.events e
where e.channel = 'release'
group by 1
order by 1 desc;

-- Each cohort (the UTC day of its first open): how many came back on day 1,
-- 3, 7, 14 and 30 — a session that day — as a share and as a count. A day
-- the cohort has not lived through yet shows null, never a false zero.
create or replace view analytics.retention as
with cohort as (
    select e.install_id, min((e.occurred_at at time zone 'UTC')::date) as day
    from public.events e
    where e.name = 'first_open' and e.channel = 'release'
    group by e.install_id
),
returned as (
    select distinct e.install_id, (e.occurred_at at time zone 'UTC')::date as day
    from public.events e
    where e.name = 'session_start' and e.channel = 'release'
)
select
    c.day                                                                    as cohort_day,
    count(distinct c.install_id)                                             as installs,
    case when c.day + 1 < (now() at time zone 'UTC')::date then round(100.0
        * count(distinct r.install_id) filter (where r.day = c.day + 1)
        / count(distinct c.install_id), 1) end                               as d1_pct,
    case when c.day + 3 < (now() at time zone 'UTC')::date then round(100.0
        * count(distinct r.install_id) filter (where r.day = c.day + 3)
        / count(distinct c.install_id), 1) end                               as d3_pct,
    case when c.day + 7 < (now() at time zone 'UTC')::date then round(100.0
        * count(distinct r.install_id) filter (where r.day = c.day + 7)
        / count(distinct c.install_id), 1) end                               as d7_pct,
    case when c.day + 14 < (now() at time zone 'UTC')::date then round(100.0
        * count(distinct r.install_id) filter (where r.day = c.day + 14)
        / count(distinct c.install_id), 1) end                               as d14_pct,
    case when c.day + 30 < (now() at time zone 'UTC')::date then round(100.0
        * count(distinct r.install_id) filter (where r.day = c.day + 30)
        / count(distinct c.install_id), 1) end                               as d30_pct,
    count(distinct r.install_id) filter (where r.day = c.day + 1)            as d1_returned,
    count(distinct r.install_id) filter (where r.day = c.day + 7)            as d7_returned,
    count(distinct r.install_id) filter (where r.day = c.day + 30)           as d30_returned
from cohort c
left join returned r on r.install_id = c.install_id and r.day between c.day + 1 and c.day + 30
group by c.day
order by c.day desc;

-- The first hour of every install that first opened the game in the last
-- 90 days: how many reached each step, as a share of those installs, and
-- the median minutes from the first open to the step. The order is the
-- guide's (Athena's opening in Lessons.swift); `skipped` is the Skip chip,
-- whenever it was pressed.
create or replace view analytics.first_hour as
with cohort as (
    select distinct e.install_id
    from public.events e
    where e.name = 'first_open' and e.channel = 'release'
      and e.occurred_at > now() - interval '90 days'
),
steps (place, step) as (
    values (0, 'first_open'), (1, 'account_guest'), (1, 'account_apple'),
           (2, 'welcome'), (3, 'first_fight'), (4, 'fight_done'),
           (5, 'first_summon'), (6, 'summon_done'), (7, 'first_relic'),
           (8, 'equip_done'), (9, 'first_powerup'), (10, 'power_up_done'),
           (11, 'farewell'), (12, 'skipped')
),
reached as (
    select c.install_id, 'first_open'::text as step, 0::numeric as minutes
    from cohort c
    union all
    select e.install_id, analytics.txt(e.props, 'step'), min(analytics.num(e.props, 'minutes'))
    from public.events e
    join cohort c on c.install_id = e.install_id
    where e.name = 'funnel' and e.channel = 'release'
    group by e.install_id, analytics.txt(e.props, 'step')
)
select
    s.place,
    s.step,
    count(r.install_id)                                                      as installs,
    round(100.0 * count(r.install_id) / nullif((select count(*) from cohort), 0), 1) as pct_of_installs,
    percentile_cont(0.5) within group (order by r.minutes)                   as median_minutes
from steps s
left join reached r on r.step = s.step
group by s.place, s.step
order by s.place, s.step;

-- Every stage fought in the last 30 days, in the game's order: attempts,
-- the installs that tried, wins, losses and forfeits, the fail rate (a loss
-- or a forfeit), first clears, and the medians that say why — the turns a
-- win took, and the team's power as a share of the stage's recommended
-- power when it won and when it failed. A stage failed at 110% of its
-- recommendation is harder than its number says. Swept runs are not here
-- (they are the sessions' `sweeps`).
create or replace view analytics.stages as
select
    analytics.txt(e.props, 'kind')                                           as kind,
    analytics.txt(e.props, 'tier')                                           as tier,
    analytics.num(e.props, 'chapter')                                        as chapter,
    analytics.num(e.props, 'index')                                          as stage_index,
    analytics.txt(e.props, 'stage')                                          as stage,
    count(*)                                                                 as attempts,
    count(distinct e.install_id)                                             as installs,
    count(*) filter (where analytics.txt(e.props, 'result') = 'won')        as won,
    count(*) filter (where analytics.txt(e.props, 'result') = 'lost')       as lost,
    count(*) filter (where analytics.txt(e.props, 'result') = 'forfeit')    as forfeited,
    round(100.0 * count(*) filter (where analytics.txt(e.props, 'result') in ('lost', 'forfeit'))
          / count(*), 1)                                                     as fail_pct,
    count(*) filter (where analytics.num(e.props, 'first') = 1)             as first_clears,
    percentile_cont(0.5) within group (order by analytics.num(e.props, 'turns'))
        filter (where analytics.txt(e.props, 'result') = 'won')             as median_turns_won,
    percentile_cont(0.5) within group (order by analytics.num(e.props, 'power_pct'))
        filter (where analytics.txt(e.props, 'result') = 'won')             as median_power_pct_won,
    percentile_cont(0.5) within group (order by analytics.num(e.props, 'power_pct'))
        filter (where analytics.txt(e.props, 'result') in ('lost', 'forfeit')) as median_power_pct_failed
from public.events e
where e.name = 'stage_result' and e.channel = 'release'
  and e.occurred_at > now() - interval '30 days'
group by 1, 2, 3, 4, 5
order by 1,
         case analytics.txt(e.props, 'tier') when 'normal' then 0 when 'hard' then 1 else 2 end,
         3, 4, 5;

-- Where the installs that stopped playing were: every install with no event
-- for seven days, by the last stage it fought and how that fight ended, and
-- one row for those that left before fighting at all (the first hour says
-- where those stopped).
create or replace view analytics.quit_points as
with gone as (
    select e.install_id
    from public.events e
    where e.channel = 'release'
    group by e.install_id
    having max(e.occurred_at) < now() - interval '7 days'
),
last_fight as (
    select distinct on (e.install_id)
        e.install_id,
        analytics.txt(e.props, 'kind')                                       as kind,
        analytics.txt(e.props, 'tier')                                       as tier,
        analytics.num(e.props, 'chapter')                                    as chapter,
        analytics.num(e.props, 'index')                                      as stage_index,
        analytics.txt(e.props, 'stage')                                      as stage,
        analytics.txt(e.props, 'result')                                     as result
    from public.events e
    join gone g on g.install_id = e.install_id
    where e.name = 'stage_result' and e.channel = 'release'
    order by e.install_id, e.occurred_at desc
),
summary as (
    select f.kind, f.tier, f.chapter, f.stage_index, f.stage, f.result, count(*) as installs
    from last_fight f
    group by f.kind, f.tier, f.chapter, f.stage_index, f.stage, f.result
    union all
    select 'none', null, null, null, 'before_any_fight', null, count(*)
    from gone g
    where not exists (select 1 from last_fight f where f.install_id = g.install_id)
)
select kind, tier, chapter, stage_index, stage, result, installs as installs_that_stopped_here
from summary
where installs > 0
order by installs desc, kind, chapter, stage_index;

-- Each UTC day's spending: summons and the pulls that found a 5★, the
-- wallet's divinity and drachma out and in (whatever moved them), energy,
-- swept runs, the upgrades that eat the soft currency, and real-money
-- purchases by count (`select … from public.events where name = 'purchase'`
-- breaks them down by product).
create or replace view analytics.economy as
select
    (e.occurred_at at time zone 'UTC')::date                                 as day,
    count(distinct e.install_id) filter (where e.name = 'summon')            as installs_summoning,
    coalesce(sum(analytics.num(e.props, 'count')) filter (where e.name = 'summon'), 0) as summons,
    count(*) filter (where e.name = 'summon' and analytics.num(e.props, 'best') >= 5) as pulls_with_a_five_star,
    coalesce(sum(analytics.num(e.props, 'divinity_spent'))  filter (where e.name = 'session_end'), 0) as divinity_spent,
    coalesce(sum(analytics.num(e.props, 'divinity_earned')) filter (where e.name = 'session_end'), 0) as divinity_earned,
    coalesce(sum(analytics.num(e.props, 'drachma_spent'))   filter (where e.name = 'session_end'), 0) as drachma_spent,
    coalesce(sum(analytics.num(e.props, 'drachma_earned'))  filter (where e.name = 'session_end'), 0) as drachma_earned,
    coalesce(sum(analytics.num(e.props, 'energy'))          filter (where e.name = 'session_end'), 0) as energy_spent,
    coalesce(sum(analytics.num(e.props, 'sweeps'))          filter (where e.name = 'session_end'), 0) as swept_runs,
    coalesce(sum(analytics.num(e.props, 'power_ups'))       filter (where e.name = 'session_end'), 0) as power_ups,
    coalesce(sum(analytics.num(e.props, 'relic_ups'))       filter (where e.name = 'session_end'), 0) as relic_upgrades,
    count(*) filter (where e.name = 'evolve')                                as evolutions,
    count(*) filter (where e.name = 'awaken')                                as awakenings,
    count(*) filter (where e.name = 'fuse')                                  as fusions,
    count(*) filter (where e.name = 'purchase')                              as purchases
from public.events e
where e.channel = 'release'
group by 1
order by 1 desc;

-- The dashboard's roles only: nothing in the schema for the app's roles.
revoke all on all tables in schema analytics from anon, authenticated;
revoke all on all functions in schema analytics from anon, authenticated;

-- ---------------------------------------------------------------------
-- Keeping it small: rows older than 120 days are deleted every night at
-- 04:17 UTC. The views read 30 and 90 days; retention's day 30 needs 60.
-- ---------------------------------------------------------------------
create or replace function analytics.prune(keep interval default interval '120 days')
returns bigint
language sql
security definer
set search_path = ''
as $$
    with gone as (
        delete from public.events where occurred_at < now() - keep returning 1
    )
    select count(*) from gone;
$$;

revoke all on function analytics.prune(interval) from public;
revoke all on function analytics.prune(interval) from anon, authenticated;

-- Supabase Cron (pg_cron) runs it; where the extension cannot be made,
-- the migration says so and goes on (Docs/ANALYTICS.md §2 schedules it by
-- hand). Scheduling the same name again replaces the job.
do $$
begin
    create extension if not exists pg_cron;
    perform cron.schedule('pantheon-analytics-prune', '17 4 * * *', 'select analytics.prune()');
exception when others then
    raise notice 'pg_cron is not available here: schedule analytics.prune() by hand (Docs/ANALYTICS.md)';
end;
$$;
