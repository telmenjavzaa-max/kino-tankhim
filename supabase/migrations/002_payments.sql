-- Кино Танхим: QPay төлбөр, эрх, видео хамгаалалт

-- Үнийн төлөвлөгөө (админ Supabase дээрээс өөрчилнө)
create table if not exists public.plans (
  code text primary key,                 -- 'sub30' | 'rent48'
  title text not null,
  amount int not null check (amount > 0),-- төгрөг
  hours int not null check (hours > 0),  -- эрх хэдэн цаг хүчинтэй
  active boolean not null default true
);
insert into public.plans (code, title, amount, hours) values
  ('sub30',  '30 хоногийн эрх', 9900, 720),
  ('rent48', 'Нэг кино 48 цаг', 3000, 48)
on conflict (code) do nothing;

-- Кино тус бүрийн түрээсийн үнэ (хоосон бол rent48-ийн үнэ)
alter table public.movies add column if not exists rent_price int check (rent_price > 0);
alter table public.movies add column if not exists has_video boolean not null default false;

-- Видео холбоосыг тусад нь, зөвхөн эрхтэй хэрэглэгчид харагдахаар
create table if not exists public.movie_videos (
  movie_id bigint primary key references public.movies on delete cascade,
  video_url text not null
);
insert into public.movie_videos (movie_id, video_url)
  select id, video_url from public.movies where coalesce(video_url, '') <> ''
on conflict (movie_id) do nothing;
alter table public.movies drop column if exists video_url;

create or replace function public.sync_has_video() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update movies set has_video = false where id = old.movie_id;
    return old;
  end if;
  update movies set has_video = true where id = new.movie_id;
  return new;
end $$;
drop trigger if exists movie_videos_sync on public.movie_videos;
create trigger movie_videos_sync after insert or update or delete on public.movie_videos
  for each row execute function public.sync_has_video();
update public.movies m set has_video = exists (select 1 from public.movie_videos v where v.movie_id = m.id);

-- Төлбөрүүд (зөвхөн серверийн функц бичнэ)
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  plan_code text not null references public.plans,
  movie_id bigint references public.movies on delete set null,
  amount int not null,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  qpay_invoice_id text,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists payments_user_idx on public.payments(user_id);
create index if not exists payments_invoice_idx on public.payments(qpay_invoice_id);

-- Үзэх эрх (movie_id хоосон = бүх кино)
create table if not exists public.entitlements (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  movie_id bigint references public.movies on delete cascade,
  payment_id uuid unique references public.payments on delete set null,
  expires_at timestamptz not null
);
create index if not exists entitlements_user_idx on public.entitlements(user_id, expires_at);

alter table public.plans enable row level security;
alter table public.movie_videos enable row level security;
alter table public.payments enable row level security;
alter table public.entitlements enable row level security;

drop policy if exists "plans are public" on public.plans;
create policy "plans are public" on public.plans for select using (active);

drop policy if exists "own payments" on public.payments;
create policy "own payments" on public.payments for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "own entitlements" on public.entitlements;
create policy "own entitlements" on public.entitlements for select to authenticated using ((select auth.uid()) = user_id);

-- Эрх шалгах
create or replace function public.has_access(p_movie bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from entitlements e
    where e.user_id = auth.uid() and e.expires_at > now()
      and (e.movie_id is null or e.movie_id = p_movie)
  );
$$;

drop policy if exists "videos for entitled users" on public.movie_videos;
create policy "videos for entitled users" on public.movie_videos for select to authenticated
  using (public.has_access(movie_id));

-- Төлбөр баталгаажуулж эрх олгох (давхар дуудсан ч нэг л удаа олгоно)
create or replace function public.grant_payment(p_payment uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  p payments%rowtype;
  pl plans%rowtype;
  base_time timestamptz;
begin
  update payments set status = 'paid', paid_at = now()
    where id = p_payment and status = 'pending'
    returning * into p;
  if not found then return false; end if;

  select * into pl from plans where code = p.plan_code;
  if p.movie_id is null then
    select greatest(now(), coalesce(max(expires_at), now())) into base_time
      from entitlements where user_id = p.user_id and movie_id is null;
  else
    base_time := now();
  end if;

  insert into entitlements (user_id, movie_id, payment_id, expires_at)
    values (p.user_id, p.movie_id, p.id, base_time + make_interval(hours => pl.hours));
  return true;
end $$;

revoke execute on function public.grant_payment(uuid) from public, anon, authenticated;
revoke execute on function public.sync_has_video() from public, anon, authenticated;
