-- AtivoFrota — carga inicial segura dos ativos da aba DADOS
-- Execute no Supabase SQL Editor antes de importar assets-import.csv.

alter table public.assets
  alter column company_id drop not null;

alter table public.assets
  add column if not exists raw_company_name text,
  add column if not exists classification_status text not null default 'pendente'
    check (classification_status in ('classificado', 'pendente', 'revisar'));

create table if not exists public.assets_import (
  legacy_id text primary key,
  name text not null,
  category text,
  brand text,
  model text,
  year text,
  company_name text,
  nf_number text,
  issue_serial text,
  operational_location text,
  chassis text,
  source_sheet text,
  source_row text,
  imported_at timestamptz not null default now()
);

alter table public.assets_import enable row level security;

drop policy if exists "Administradores gerenciam carga de ativos" on public.assets_import;
create policy "Administradores gerenciam carga de ativos"
on public.assets_import
for all
to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Permite ao administrador visualizar ativos ainda sem empresa definida.
drop policy if exists "Administradores podem visualizar ativos pendentes" on public.assets;
create policy "Administradores podem visualizar ativos pendentes"
on public.assets
for select
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  or exists (select 1 from public.user_companies uc where uc.user_id = auth.uid() and uc.company_id = assets.company_id)
);

drop policy if exists "Administradores gerenciam todos os ativos" on public.assets;
create policy "Administradores gerenciam todos os ativos"
on public.assets
for all
to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Após importar assets-import.csv em public.assets_import, execute este bloco.
insert into public.assets (
  legacy_id, name, company_id, category, brand, model, year,
  operational_location, chassis, status, raw_company_name,
  classification_status, created_at, updated_at
)
select
  i.legacy_id,
  i.name,
  c.id,
  nullif(i.category, ''),
  nullif(i.brand, ''),
  nullif(i.model, ''),
  case when i.year ~ '^[0-9]{4}$' then i.year::integer else null end,
  nullif(i.operational_location, ''),
  nullif(i.chassis, ''),
  'Pendente',
  nullif(i.company_name, ''),
  case
    when c.id is not null then 'classificado'
    when nullif(i.company_name, '') is null then 'pendente'
    else 'revisar'
  end,
  now(), now()
from public.assets_import i
left join public.companies c
  on upper(trim(c.name)) = upper(trim(i.company_name))
where not exists (
  select 1 from public.assets a where a.legacy_id = i.legacy_id
);

-- Validação da carga.
select
  count(*) as total_importado,
  count(*) filter (where classification_status = 'classificado') as classificados,
  count(*) filter (where classification_status in ('pendente', 'revisar')) as para_revisao
from public.assets;

select classification_status, raw_company_name, count(*)
from public.assets
where classification_status <> 'classificado'
group by classification_status, raw_company_name
order by classification_status, count(*) desc;
