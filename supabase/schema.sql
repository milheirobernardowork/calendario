-- Agenda: esquema da base de dados.
-- Corre este ficheiro uma vez em Supabase → SQL Editor.

create table if not exists public.events (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '',
  notes text not null default '',
  start_at timestamptz not null,
  end_at timestamptz not null,
  all_day boolean not null default false,
  color integer not null default 0,
  recurrence jsonb,
  category text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.tasks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '',
  notes text not null default '',
  due_date date,
  done boolean not null default false,
  active boolean not null default false,
  priority integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Colunas acrescentadas depois da primeira versão.
alter table public.tasks add column if not exists active boolean not null default false;
alter table public.events add column if not exists recurrence jsonb;
alter table public.events add column if not exists category text;

-- Colunas da página Eventos (ex.: "Corridas").
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

create index if not exists events_user_idx on public.events (user_id);
create index if not exists tasks_user_idx on public.tasks (user_id);

-- Cada utilizador só vê e altera os seus próprios dados.
alter table public.events enable row level security;
alter table public.tasks enable row level security;

drop policy if exists "own events" on public.events;
create policy "own events" on public.events
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "own tasks" on public.tasks;
create policy "own tasks" on public.tasks
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Sincronização em tempo real entre dispositivos.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'events'
  ) then
    alter publication supabase_realtime add table public.events;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'tasks'
  ) then
    alter publication supabase_realtime add table public.tasks;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'categories'
  ) then
    alter publication supabase_realtime add table public.categories;
  end if;
end $$;
