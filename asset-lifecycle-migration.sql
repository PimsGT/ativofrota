-- AtivoFrota — cadeia de registro do bem
-- Execute este arquivo inteiro no Supabase SQL Editor.
-- A ordem é intencional: primeiro cria as colunas; depois cria eventos e gatilho.
-- Não apaga nem reclassifica automaticamente os ativos existentes.

-- ============================================================
-- 1. Colunas do ciclo de vida em public.assets
-- ============================================================

alter table public.assets
  add column if not exists lifecycle_status text;

alter table public.assets
  add column if not exists buyer_name text;

alter table public.assets
  add column if not exists sale_date date;

alter table public.assets
  add column if not exists sale_document_name text;

alter table public.assets
  add column if not exists sale_notes text;

alter table public.assets
  add column if not exists origin_company_id uuid;

alter table public.assets
  add column if not exists current_company_id uuid;

-- Preenche somente valores vazios. Registros existentes não são vendidos nem baixados.
update public.assets
set lifecycle_status = 'ATIVO'
where lifecycle_status is null;

update public.assets
set origin_company_id = company_id
where origin_company_id is null
  and company_id is not null;

update public.assets
set current_company_id = company_id
where current_company_id is null
  and company_id is not null;

-- Restrições aplicadas depois que a coluna já existe.
alter table public.assets
  alter column lifecycle_status set default 'ATIVO';

alter table public.assets
  alter column lifecycle_status set not null;

alter table public.assets
  drop constraint if exists assets_lifecycle_status_check;

alter table public.assets
  add constraint assets_lifecycle_status_check
  check (lifecycle_status in ('ATIVO', 'VENDIDO', 'BAIXADO', 'TRANSFERIDO', 'REVISAR'));

-- ============================================================
-- 2. Histórico imutável dos eventos do ativo
-- ============================================================

create table if not exists public.asset_events (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete cascade,
  event_type text not null check (event_type in ('CADASTRO', 'TRANSFERENCIA', 'VENDA', 'BAIXA', 'RECLASSIFICACAO', 'DOCUMENTO')),
  event_date date not null default current_date,
  from_company_id uuid,
  to_company_id uuid,
  counterparty_name text,
  document_name text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists asset_events_asset_date_idx
  on public.asset_events(asset_id, event_date desc, created_at desc);

alter table public.asset_events enable row level security;

drop policy if exists "Usuários autenticados consultam histórico de ativos" on public.asset_events;
create policy "Usuários autenticados consultam histórico de ativos"
on public.asset_events
for select to authenticated
using (true);

drop policy if exists "Usuários autenticados registram histórico de ativos" on public.asset_events;
create policy "Usuários autenticados registram histórico de ativos"
on public.asset_events
for insert to authenticated
with check (created_by = auth.uid() or created_by is null);

-- ============================================================
-- 3. Índices para filtros de ciclo de vida
-- ============================================================

create index if not exists assets_lifecycle_status_idx
  on public.assets(lifecycle_status);

create index if not exists assets_buyer_name_idx
  on public.assets(buyer_name);

create index if not exists assets_sale_date_idx
  on public.assets(sale_date);

-- ============================================================
-- 4. Gatilho para registrar alterações futuras
-- ============================================================

create or replace function public.record_asset_lifecycle_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.asset_events(
      asset_id, event_type, event_date, to_company_id,
      counterparty_name, notes, created_by
    )
    values (
      new.id, 'CADASTRO', current_date, new.current_company_id,
      new.buyer_name, 'Cadastro inicial do ativo', auth.uid()
    );
    return new;
  end if;

  -- Uma transferência pode alterar empresa e ciclo de vida na mesma operação.
  -- A mudança de empresa precisa prevalecer para preservar o evento correto.
  if old.current_company_id is distinct from new.current_company_id
     or old.company_id is distinct from new.company_id then
    insert into public.asset_events(
      asset_id, event_type, event_date, from_company_id, to_company_id,
      notes, created_by
    )
    values (
      new.id, 'TRANSFERENCIA', current_date,
      old.current_company_id, new.current_company_id,
      'Transferência de empresa', auth.uid()
    );
  elsif old.lifecycle_status is distinct from new.lifecycle_status then
    insert into public.asset_events(
      asset_id, event_type, event_date, from_company_id, to_company_id,
      counterparty_name, document_name, notes, created_by
    )
    values (
      new.id,
      case new.lifecycle_status
        when 'VENDIDO' then 'VENDA'
        when 'BAIXADO' then 'BAIXA'
        else 'RECLASSIFICACAO'
      end,
      coalesce(new.sale_date, current_date),
      old.current_company_id,
      new.current_company_id,
      new.buyer_name,
      new.sale_document_name,
      new.sale_notes,
      auth.uid()
    );
  elsif old.buyer_name is distinct from new.buyer_name
     or old.sale_date is distinct from new.sale_date
     or old.sale_document_name is distinct from new.sale_document_name
     or old.sale_notes is distinct from new.sale_notes then
    insert into public.asset_events(
      asset_id, event_type, event_date, counterparty_name,
      document_name, notes, created_by
    )
    values (
      new.id, 'VENDA', coalesce(new.sale_date, current_date),
      new.buyer_name, new.sale_document_name, new.sale_notes, auth.uid()
    );
  end if;

  return new;
end;
$$;

drop trigger if exists assets_record_lifecycle_event on public.assets;

create trigger assets_record_lifecycle_event
after insert or update of lifecycle_status, current_company_id,
  buyer_name, sale_date, sale_document_name, sale_notes
on public.assets
for each row execute function public.record_asset_lifecycle_event();

-- ============================================================
-- 5. Conferência final
-- ============================================================

select
  count(*) as total_historico,
  count(*) filter (where lifecycle_status in ('ATIVO', 'TRANSFERIDO')) as patrimonio_atual,
  count(*) filter (where lifecycle_status = 'VENDIDO') as vendidos,
  count(*) filter (where lifecycle_status = 'BAIXADO') as baixados,
  count(*) filter (where lifecycle_status = 'REVISAR') as revisar
from public.assets;
