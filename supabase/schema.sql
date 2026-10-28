-- Кино Танхим: өгөгдлийн сангийн бүтэц
create table if not exists public.movies (
  id bigint generated always as identity primary key,
  title text not null,
  year int,
  genre text,
  runtime int,                -- минутаар
  description text,
  poster_url text,            -- Supabase Storage (posters bucket) эсвэл өөр https холбоос
  video_url text,             -- Bunny Stream / Kinescope / Vimeo холбоос
  hue1 int default 30,
  hue2 int default 220,
  featured boolean default false,
  published boolean default true,
  created_at timestamptz default now()
);

create table if not exists public.favorites (
  user_id uuid not null references auth.users on delete cascade,
  movie_id bigint not null references public.movies on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, movie_id)
);

alter table public.movies enable row level security;
alter table public.favorites enable row level security;

-- Нийтлэгдсэн киног хэн ч харж болно (видео холбоосыг тоглуулахад нэвтрэлт шаардана — сайт талд)
drop policy if exists "movies are public" on public.movies;
create policy "movies are public" on public.movies for select using (published = true);

drop policy if exists "own favorites read" on public.favorites;
create policy "own favorites read" on public.favorites for select using (auth.uid() = user_id);
drop policy if exists "own favorites add" on public.favorites;
create policy "own favorites add" on public.favorites for insert with check (auth.uid() = user_id);
drop policy if exists "own favorites remove" on public.favorites;
create policy "own favorites remove" on public.favorites for delete using (auth.uid() = user_id);

-- Постерийн нийтийн bucket
insert into storage.buckets (id, name, public) values ('posters', 'posters', true)
on conflict (id) do nothing;

-- Туршилтын кинонууд
insert into public.movies (title, year, genre, runtime, hue1, hue2, poster_url, description, featured) values
('Талын салхи', 2025, 'Драм', 112, 35, 15, 'https://jaqapcgokfkrioydxgmk.supabase.co/storage/v1/object/public/posters/talyn-salkhi.jpg', 'Хотоос буцаж ирсэн залуу эцгийнхээ адуун сүргийг авч үлдэхийн тулд өвлийн зудтай тэмцэнэ.', true),
('Шөнийн Улаанбаатар', 2025, 'Триллер', 104, 350, 190, 'https://jaqapcgokfkrioydxgmk.supabase.co/storage/v1/object/public/posters/shoniin-ub.jpg', 'Утаат өвлийн шөнө такси жолооч санамсаргүйгээр гэмт хэргийн гэрч болж, үүр цайхаас өмнө үнэнийг олох ёстой болно.', false),
('Мөнх тэнгэрийн дор', 2024, 'Түүхэн', 138, 215, 40, 'https://jaqapcgokfkrioydxgmk.supabase.co/storage/v1/object/public/posters/monkh-tengeriin-dor.jpg', 'XIII зууны тал нутагт залуу харуул овгуудыг нэгтгэх их аянд өөрийн байр сууриа олно.', false),
('Сүүлчийн нүүдэл', 2025, 'Адал явдалт', 97, 25, 45, 'https://jaqapcgokfkrioydxgmk.supabase.co/storage/v1/object/public/posters/suulchiin-nuudel.jpg', 'Малчин гэр бүл ган гачигтай зун Говийг гатлан шинэ нутаг хайж, сүүлчийн удаа нүүнэ.', false),
('Хөх толбо', 2025, 'Инээдмийн', 92, 210, 50, 'https://jaqapcgokfkrioydxgmk.supabase.co/storage/v1/object/public/posters/khokh-tolbo.jpg', 'Гэнэт эгчийнхээ хүүхдийг долоо хоног харахаар болсон ганц бие залуугийн инээдтэй адал явдал.', false),
('Чимээгүй хөндий', 2025, 'Аймшгийн', 99, 150, 200, 'https://jaqapcgokfkrioydxgmk.supabase.co/storage/v1/object/public/posters/chimeegui-khondii.jpg', 'Уулын хөндийд зуны амралтаараа очсон найзууд хаягдсан гэрээс шөнө бүр гэрэл асахыг анзаарна.', false);
