-- EventLens AI allowance. Counts only: no text, photos or memories are
-- stored. Only the AI server (service role) touches these; row level
-- security is on with no policies, so the public API can't read them.

create table public.ai_usage (
  uid   text    not null,
  day   date    not null,
  used  integer not null default 0 check (used >= 0),
  bonus integer not null default 0 check (bonus >= 0),
  primary key (uid, day)
);

create table public.ai_ad_rewards (
  transaction_id text        primary key,
  uid            text        not null,
  day            date        not null,
  credits        integer     not null,
  created_at     timestamptz not null default now()
);

alter table public.ai_usage enable row level security;
alter table public.ai_ad_rewards enable row level security;

-- Credits left today (never below zero).
create function public.ai_allowance(p_uid text, p_day date, p_daily integer)
returns integer
language sql
stable
as $$
  select greatest(
    coalesce(
      (select p_daily + bonus - used from public.ai_usage
        where uid = p_uid and day = p_day),
      p_daily),
    0);
$$;

-- Uses p_cost credits if that many are left; atomic, so two requests at
-- once can't both spend the last credits.
create function public.ai_consume(
  p_uid text, p_day date, p_cost integer, p_daily integer)
returns table (ok boolean, remaining integer)
language plpgsql
as $$
declare
  left_after integer;
begin
  insert into public.ai_usage (uid, day) values (p_uid, p_day)
    on conflict do nothing;
  update public.ai_usage
     set used = used + p_cost
   where uid = p_uid and day = p_day
     and p_daily + bonus - used >= p_cost
  returning p_daily + bonus - used into left_after;
  if left_after is null then
    return query select false, public.ai_allowance(p_uid, p_day, p_daily);
  else
    return query select true, left_after;
  end if;
end;
$$;

-- Gives credits back when the AI request failed.
create function public.ai_refund(p_uid text, p_day date, p_cost integer)
returns void
language sql
as $$
  update public.ai_usage
     set used = greatest(used - p_cost, 0)
   where uid = p_uid and day = p_day;
$$;

-- Adds a reward video's credits once per AdMob transaction.
create function public.ai_add_bonus(
  p_tx text, p_uid text, p_day date, p_credits integer)
returns boolean
language plpgsql
as $$
begin
  insert into public.ai_ad_rewards (transaction_id, uid, day, credits)
    values (p_tx, p_uid, p_day, p_credits)
    on conflict (transaction_id) do nothing;
  if not found then
    return false;
  end if;
  insert into public.ai_usage (uid, day, bonus) values (p_uid, p_day, p_credits)
    on conflict (uid, day) do update
      set bonus = public.ai_usage.bonus + excluded.bonus;
  return true;
end;
$$;

revoke all on function public.ai_allowance(text, date, integer) from public, anon, authenticated;
revoke all on function public.ai_consume(text, date, integer, integer) from public, anon, authenticated;
revoke all on function public.ai_refund(text, date, integer) from public, anon, authenticated;
revoke all on function public.ai_add_bonus(text, text, date, integer) from public, anon, authenticated;
