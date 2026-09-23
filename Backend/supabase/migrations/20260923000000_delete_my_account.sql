-- Pantheon backend, account deletion (2026-09-23; Docs/BACKEND.md §7,
-- Docs/SETTINGS.md §3): App Review Guideline 5.1.1(v) asks an app that
-- creates accounts to delete them from inside the app. Run once in the
-- project's SQL editor (Dashboard → SQL Editor → New query → paste → Run),
-- or with `supabase db push`, after 20260922000000_players_saves.sql.
-- Re-running it is safe (`create or replace`, and grants are idempotent).
--
-- The app calls it as POST /rest/v1/rpc/delete_my_account with the player's
-- own session (AccountDeletion in Pantheon/Core/Account). It deletes the
-- CALLER and nobody else: the only id it reads is auth.uid(), the user the
-- request's JWT names. The save and the player row go first (they cascade
-- from the user anyway; explicit deletes keep this true if a foreign key is
-- ever changed), then the auth user, which takes its identities, sessions
-- and refresh tokens with it.

create or replace function public.delete_my_account()
returns void
language plpgsql
-- The caller cannot delete from auth.users; the function's owner can. So
-- it runs as its owner — which is why search_path is pinned empty and every
-- name below is schema-qualified (Supabase: a security definer function must
-- set search_path).
security definer
set search_path = ''
as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    delete from public.saves   where player_id = uid;
    delete from public.players where id = uid;
    delete from auth.users     where id = uid;
end;
$$;

comment on function public.delete_my_account() is
    'Deletes the calling user: its save, its player row and its auth user (Docs/BACKEND.md §7).';

-- Signed-in users only. Postgres grants EXECUTE to PUBLIC on a new function,
-- and Supabase's default privileges grant it to anon as well, so both are
-- revoked before the one grant that matters.
revoke execute on function public.delete_my_account() from public;
revoke execute on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;
