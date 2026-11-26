-- AtivoFrota — catálogo enxuto e histórico de mesclagens de categorias
-- Aplicar no projeto Supabase após a estrutura base.
-- assets.category permanece textual nesta primeira etapa.

create table if not exists public.asset_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists asset_categories_name_uidx
  on public.asset_categories (lower(trim(name)));
create index if not exists asset_categories_active_order_idx
  on public.asset_categories (active, sort_order, name);

insert into public.asset_categories (name, sort_order)
select trim(a.category), 100
from public.assets a
where a.category is not null and trim(a.category) <> ''
on conflict do nothing;

insert into public.asset_categories (name, sort_order)
values
  ('TRATOR', 10), ('PLANTADEIRA', 20), ('CAMINHÃO', 30), ('COLHETADEIRA', 40),
  ('PLATAFORMA', 50), ('PULVERIZADOR', 60), ('DISTRIBUIDOR', 70),
  ('CARRETA GRANEIRA', 80), ('CAMINHONETE', 90), ('PÁ CARREGADEIRA', 100),
  ('GRADE ARADORA', 110), ('OUTROS', 999)
on conflict do nothing;

create table if not exists public.asset_category_merge_log (
  id uuid primary key default gen_random_uuid(),
  source_category_id uuid not null references public.asset_categories(id),
  target_category_id uuid not null references public.asset_categories(id),
  source_category_name text not null,
  target_category_name text not null,
  assets_migrated integer not null default 0,
  performed_by uuid not null references auth.users(id),
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists asset_category_merge_log_created_idx on public.asset_category_merge_log(created_at desc);

create or replace function public.merge_asset_category(source_id uuid, target_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  source_name text;
  target_name text;
  migrated integer;
begin
  if not public.is_master() then raise exception 'Apenas o usuário Master pode mesclar categorias'; end if;
  if source_id = target_id then raise exception 'A categoria de origem e destino devem ser diferentes'; end if;
  select name into source_name from public.asset_categories where id = source_id and active = true;
  select name into target_name from public.asset_categories where id = target_id and active = true;
  if source_name is null or target_name is null then raise exception 'As duas categorias precisam estar ativas'; end if;
  update public.assets set category = target_name, updated_at = timezone('utc', now()) where category = source_name;
  get diagnostics migrated = row_count;
  insert into public.asset_category_merge_log(source_category_id,target_category_id,source_category_name,target_category_name,assets_migrated,performed_by)
  values(source_id,target_id,source_name,target_name,migrated,auth.uid());
  update public.asset_categories set active = false, updated_at = timezone('utc', now()) where id = source_id;
  return migrated;
end;
$$;
revoke all on function public.merge_asset_category(uuid, uuid) from public;
grant execute on function public.merge_asset_category(uuid, uuid) to authenticated;

alter table public.asset_categories enable row level security;
drop policy if exists "Usuários ativos consultam categorias" on public.asset_categories;
create policy "Usuários ativos consultam categorias" on public.asset_categories for select to authenticated
using (active = true and exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true));
drop policy if exists "Master administra categorias" on public.asset_categories;
create policy "Master administra categorias" on public.asset_categories for all to authenticated using (public.is_master()) with check (public.is_master());

alter table public.asset_category_merge_log enable row level security;
drop policy if exists "Master consulta histórico de categorias" on public.asset_category_merge_log;
create policy "Master consulta histórico de categorias" on public.asset_category_merge_log for select to authenticated using (public.is_master());
