-- AtivoFrota — catálogo administrável de categorias
-- Aplicar no projeto Supabase após a estrutura base.
-- A coluna assets.category permanece textual nesta primeira etapa para preservar compatibilidade.

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

-- Importa categorias que já existem nos ativos antes de inserir os padrões.
insert into public.asset_categories (name, sort_order)
select trim(a.category), 100
from public.assets a
where a.category is not null and trim(a.category) <> ''
on conflict do nothing;

insert into public.asset_categories (name, sort_order)
values
  ('TRATOR', 10),
  ('PLANTADEIRA', 20),
  ('CAMINHÃO', 30),
  ('COLHETADEIRA', 40),
  ('PLATAFORMA', 50),
  ('PULVERIZADOR', 60),
  ('DISTRIBUIDOR', 70),
  ('CARRETA GRANEIRA', 80),
  ('CAMINHONETE', 90),
  ('PÁ CARREGADEIRA', 100),
  ('GRADE ARADORA', 110),
  ('OUTROS', 999)
on conflict do nothing;

alter table public.asset_categories enable row level security;

drop policy if exists "Usuários ativos consultam categorias" on public.asset_categories;
create policy "Usuários ativos consultam categorias"
on public.asset_categories for select to authenticated
using (
  active = true
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true)
);

drop policy if exists "Master administra categorias" on public.asset_categories;
create policy "Master administra categorias"
on public.asset_categories for all to authenticated
using (public.is_master())
with check (public.is_master());

-- Não permite inativar uma categoria ainda necessária sem que ela continue visível ao ativo.
comment on table public.asset_categories is 'Catálogo de categorias; exclusão lógica por active, administração exclusiva do perfil Master.';
