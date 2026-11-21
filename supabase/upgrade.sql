-- WolfCal: atualização da base de dados (tarefas ativas, repetições,
-- página Eventos). Pode ser corrida mais do que uma vez.

alter table public.tasks add column if not exists active boolean not null default false;
alter table public.tasks add column if not exists future boolean not null default false;
alter table public.tasks add column if not exists created_at timestamptz;
alter table public.events add column if not exists recurrence jsonb;
alter table public.events add column if not exists category text;

create table if not exists public.categories (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.categories enable row level security;
drop policy if exists "own categories" on public.categories;
create policy "own categories" on public.categories
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'categories'
  ) then
    alter publication supabase_realtime add table public.categories;
  end if;
end $$;

-- Põe a "Meia Maratona dos Descobrimentos" na coluna Corridas (a coluna é
-- criada pela app) e completa o título, que veio cortado do PDF.
update public.events
set category = 'c0a1c0a1-0000-4000-8000-00000000c0a1',
    title = 'Meia Maratona dos Descobrimentos',
    updated_at = now()
where title ilike 'Meia Maratona dos%'
  and (start_at at time zone 'Europe/Lisbon')::date between '2026-11-28' and '2026-11-29';

-- Workspace: páginas de notas (blocos em JSON), arrumadas em pastas.
create table if not exists public.pages (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '',
  folder text not null default '',
  color integer not null default 0,
  position integer not null default 0,
  blocks jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.pages enable row level security;
drop policy if exists "own pages" on public.pages;
create policy "own pages" on public.pages
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'pages'
  ) then
    alter publication supabase_realtime add table public.pages;
  end if;
end $$;
