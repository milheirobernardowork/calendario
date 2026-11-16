-- WolfCal: os eventos roxos são aniversários e passam a repetir todos os
-- anos. Pode ser corrido mais do que uma vez.

-- 1. Apagar cópias soltas de aniversários que já têm uma repetição anual
--    (ou que aparecem em mais do que um ano), para não ficarem a dobrar.
with roxos as (
  select id, lower(trim(title)) as nome, start_at, recurrence
  from public.events
  where color = 4 and deleted_at is null
),
com_serie as (
  select distinct nome from roxos where recurrence is not null
),
duplicados as (
  select r.id from roxos r join com_serie s using (nome)
  where r.recurrence is null
  union
  select r.id from roxos r
  where r.recurrence is null
    and r.nome not in (select nome from com_serie)
    and exists (
      select 1 from roxos o
      where o.nome = r.nome and o.recurrence is null and o.start_at < r.start_at
        and to_char(o.start_at at time zone 'Europe/Lisbon', 'MM-DD')
          = to_char(r.start_at at time zone 'Europe/Lisbon', 'MM-DD')
    )
)
update public.events
set deleted_at = now(), updated_at = now()
where id in (select id from duplicados);

-- 2. Os restantes passam a repetir todos os anos.
update public.events
set recurrence = '{"unit": "year", "interval": 1}'::jsonb, updated_at = now()
where color = 4 and deleted_at is null and recurrence is null;

-- 3. Resultado: todos os roxos, com a repetição.
select title, (start_at at time zone 'Europe/Lisbon')::date as dia, recurrence
from public.events
where color = 4 and deleted_at is null
order by to_char(start_at at time zone 'Europe/Lisbon', 'MM-DD');
