-- AtivoFrota — sequência consolidada de correções
-- Revisar e executar no SQL Editor do projeto correto.
-- Não inclui scripts de importação.
-- Ordem: perfis -> RLS -> ciclo de vida -> hardening -> auditoria -> Storage -> limpeza legada.

-- ===== INÍCIO: supabase-user-access.sql =====

-- AtivoFrota: perfis e primeiro acesso
-- Execute no Supabase SQL Editor antes de usar a tela Administração > Usuários.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('master', 'patrimonial')),
  must_change_password boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

-- Compatibilidade com uma tabela profiles criada antes desta migração.
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists role text;
alter table public.profiles add column if not exists must_change_password boolean not null default true;
alter table public.profiles add column if not exists active boolean not null default true;
alter table public.profiles add column if not exists created_at timestamptz not null default timezone('utc', now());
alter table public.profiles add column if not exists updated_at timestamptz not null default timezone('utc', now());

update public.profiles
set display_name = coalesce(nullif(display_name, ''), 'Usuário AtivoFrota'),
    role = case when role in ('master', 'patrimonial') then role else 'patrimonial' end,
    must_change_password = coalesce(must_change_password, true),
    active = coalesce(active, true)
where display_name is null
   or display_name = ''
   or role is null
   or role not in ('master', 'patrimonial')
   or must_change_password is null
   or active is null;

alter table public.profiles alter column display_name set not null;
alter table public.profiles alter column role set not null;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('master', 'patrimonial'));

create index if not exists profiles_role_idx on public.profiles(role);

alter table public.profiles enable row level security;

create or replace function public.is_master()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'master' and active = true
  );
$$;

revoke all on function public.is_master() from public;
grant execute on function public.is_master() to authenticated;

drop policy if exists "profiles_select_self_or_master" on public.profiles;
create policy "profiles_select_self_or_master"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_master());

drop policy if exists "profiles_insert_master" on public.profiles;
create policy "profiles_insert_master"
on public.profiles for insert to authenticated
with check (public.is_master());

drop policy if exists "profiles_update_self_password_or_master" on public.profiles;
create policy "profiles_update_self_password_or_master"
on public.profiles for update to authenticated
using (id = auth.uid() or public.is_master())
with check (
  public.is_master()
  or (
    id = auth.uid()
    and role = (select p.role from public.profiles p where p.id = auth.uid())
    and active = (select p.active from public.profiles p where p.id = auth.uid())
    and must_change_password = false
  )
);

create or replace function public.set_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_profile_updated_at();

-- Depois de executar este arquivo, cadastre manualmente o primeiro master:
-- insert into public.profiles (id, display_name, role, must_change_password)
-- values ('UUID_DO_USUARIO_AUTH', 'Leonardo Aguiar', 'master', false);


-- ===== FIM: supabase-user-access.sql =====

-- ===== INÍCIO: assets-rls-master-access.sql =====

-- AtivoFrota — acesso à base e correção de ativos sem classificação
-- Execute este arquivo inteiro no Supabase SQL Editor.
-- Regra de negócio:
--   1) ativos sem company_id são visíveis para todos os usuários ativos;
--   2) ativos sem company_id podem ser corrigidos pelos operadores;
--   3) ativos classificados ficam limitados à empresa autorizada;
--   4) Master vê e gerencia todos os ativos.

alter table public.assets enable row level security;

-- Remove políticas antigas incompatíveis com o modelo master/patrimonial.
drop policy if exists "Administradores podem visualizar ativos pendentes" on public.assets;
drop policy if exists "Administradores gerenciam todos os ativos" on public.assets;
drop policy if exists "Master visualiza todos os ativos" on public.assets;
drop policy if exists "Master gerencia todos os ativos" on public.assets;
drop policy if exists "Usuários visualizam ativos das empresas" on public.assets;
drop policy if exists "Usuários ativos consultam ativos" on public.assets;
drop policy if exists "Operadores corrigem ativos sem classificação" on public.assets;

-- SELECT: ativos sem empresa aparecem para todos os usuários ativos.
create policy "Usuários ativos consultam ativos"
on public.assets
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active = true
  )
  and (
    company_id is null
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'master'
        and p.active = true
    )
    or exists (
      select 1
      from public.user_companies uc
      where uc.user_id = auth.uid()
        and uc.company_id = public.assets.company_id
    )
  )
);

-- UPDATE: Master pode alterar qualquer ativo.
drop policy if exists "Master atualiza todos os ativos" on public.assets;
create policy "Master atualiza todos os ativos"
on public.assets
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'master'
      and p.active = true
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'master'
      and p.active = true
  )
);

-- UPDATE: operador pode corrigir ativo sem classificação ou ativo da sua empresa.
-- Ao classificar, a empresa de destino precisa estar vinculada ao operador.
create policy "Operadores corrigem ativos sem classificação"
on public.assets
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active = true
      and p.role in ('master', 'patrimonial')
  )
  and (
    company_id is null
    or exists (
      select 1
      from public.user_companies uc
      where uc.user_id = auth.uid()
        and uc.company_id = public.assets.company_id
    )
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active = true
      and p.role in ('master', 'patrimonial')
  )
  and (
    company_id is null
    or exists (
      select 1
      from public.user_companies uc
      where uc.user_id = auth.uid()
        and uc.company_id = public.assets.company_id
    )
  )
);

-- INSERT: somente Master cadastra novos ativos diretamente.
drop policy if exists "Master insere ativos" on public.assets;
create policy "Master insere ativos"
on public.assets
for insert
to authenticated
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'master'
      and p.active = true
  )
);

-- DELETE: somente Master remove registros.
drop policy if exists "Master remove ativos" on public.assets;
create policy "Master remove ativos"
on public.assets
for delete
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'master'
      and p.active = true
  )
);

-- Conferência: execute conectado com o usuário Master.
select count(*) as total_visivel_para_master
from public.assets;

-- Conferência: ativos ainda aguardando classificação.
select count(*) as total_sem_classificacao
from public.assets
where company_id is null;


-- ===== FIM: assets-rls-master-access.sql =====

-- ===== INÍCIO: asset-lifecycle-migration.sql =====

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


-- ===== FIM: asset-lifecycle-migration.sql =====

-- ===== INÍCIO: supabase\production-hardening.sql =====

-- AtivoFrota — endurecimento para produção
-- Execute após supabase-user-access.sql, assets-rls-master-access.sql e asset-lifecycle-migration.sql.

-- Usuário comum não pode alterar identidade, perfil, status ou liberar a troca de senha.
drop policy if exists "profiles_update_self_password_or_master" on public.profiles;
create policy "profiles_update_self_password_or_master"
on public.profiles for update to authenticated
using (id = auth.uid() or public.is_master())
with check (
  public.is_master()
  or (
    id = auth.uid()
    and display_name = (select p.display_name from public.profiles p where p.id = auth.uid())
    and role = (select p.role from public.profiles p where p.id = auth.uid())
    and active = (select p.active from public.profiles p where p.id = auth.uid())
    and must_change_password = false
  )
);

-- Operadores não podem devolver ativos classificados para o conjunto aberto.
drop policy if exists "Operadores corrigem ativos sem classificação" on public.assets;
create policy "Operadores corrigem ativos sem classificação"
on public.assets for update to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true and p.role in ('master','patrimonial'))
  and (
    company_id is null
    or exists (select 1 from public.user_companies uc where uc.user_id = auth.uid() and uc.company_id = public.assets.company_id)
  )
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true and p.role in ('master','patrimonial'))
  and company_id is not null
  and (
    public.is_master()
    or exists (select 1 from public.user_companies uc where uc.user_id = auth.uid() and uc.company_id = public.assets.company_id)
  )
);

-- Empresas e vínculos: leitura para usuários ativos; manutenção somente pelo Master.
alter table public.companies enable row level security;
drop policy if exists "Usuários ativos consultam empresas" on public.companies;
create policy "Usuários ativos consultam empresas" on public.companies for select to authenticated using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true));
drop policy if exists "Master gerencia empresas" on public.companies;
create policy "Master gerencia empresas" on public.companies for all to authenticated using (public.is_master()) with check (public.is_master());

alter table public.user_companies enable row level security;
drop policy if exists "Usuário consulta seus vínculos" on public.user_companies;
create policy "Usuário consulta seus vínculos" on public.user_companies for select to authenticated using (user_id = auth.uid() or public.is_master());
drop policy if exists "Master gerencia vínculos" on public.user_companies;
create policy "Master gerencia vínculos" on public.user_companies for all to authenticated using (public.is_master()) with check (public.is_master());

-- Documentos: usuário ativo consulta; inclusão depende do acesso ao ativo ou de ser Master.
alter table public.asset_documents enable row level security;
drop policy if exists "Usuários consultam documentos autorizados" on public.asset_documents;
create policy "Usuários consultam documentos autorizados" on public.asset_documents for select to authenticated using (public.is_master() or exists (select 1 from public.assets a where a.id = asset_documents.asset_id));
drop policy if exists "Usuários inserem documentos autorizados" on public.asset_documents;
create policy "Usuários inserem documentos autorizados"
on public.asset_documents for insert to authenticated
with check (
  public.is_master()
  or (
    asset_documents.asset_id is not null
    and exists (select 1 from public.assets a where a.id = asset_documents.asset_id)
  )
  or (
    asset_documents.asset_id is null
    and exists (
      select 1
      from public.user_companies uc
      where uc.user_id = auth.uid()
        and uc.company_id = asset_documents.company_id
    )
  )
);

-- Bucket privado: os arquivos só devem ser acessados por URLs assinadas emitidas pelo app.
insert into storage.buckets (id, name, public) values ('ativos-documentos', 'ativos-documentos', false) on conflict (id) do update set public = false;

create or replace function public.can_access_asset_storage(path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  asset_uuid uuid;
begin
  if public.is_master() then
    return true;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.active = true
  ) then
    return false;
  end if;

  if path !~ '^assets/[0-9a-fA-F-]{36}/(documents|photos)/' then
    return false;
  end if;

  begin
    asset_uuid := split_part(path, '/', 2)::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  return exists (
    select 1
    from public.assets a
    join public.user_companies uc
      on uc.company_id = coalesce(a.current_company_id, a.company_id)
     and uc.user_id = auth.uid()
    where a.id = asset_uuid
  );
end;
$$;

revoke all on function public.can_access_asset_storage(text) from public;
grant execute on function public.can_access_asset_storage(text) to authenticated;

drop policy if exists "Usuários autenticados leem documentos" on storage.objects;
drop policy if exists "Usuários autorizados leem documentos" on storage.objects;
create policy "Usuários autorizados leem documentos"
on storage.objects for select to authenticated
using (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (name like 'imports/%' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true))
  )
);

drop policy if exists "Usuários autenticados enviam documentos" on storage.objects;
drop policy if exists "Usuários autorizados enviam documentos" on storage.objects;
create policy "Usuários autorizados enviam documentos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (name like 'imports/%' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true))
  )
);

-- O app trabalha com o tamanho máximo de 25 MB; a validação também deve ser mantida no bucket/proxy escolhido.


-- ===== FIM: supabase\production-hardening.sql =====

-- ===== INÍCIO: supabase\audit-monitor-migration.sql =====

-- AtivoFrota — monitor de auditoria Master
-- Execute após as migrações existentes do projeto.

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  company_id uuid references public.companies(id),
  actor_id uuid references auth.users(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists audit_events_created_at_idx on public.audit_events(created_at desc);
create index if not exists audit_events_company_idx on public.audit_events(company_id, created_at desc);
create index if not exists audit_events_type_idx on public.audit_events(event_type, created_at desc);

alter table public.audit_events enable row level security;
drop policy if exists "Somente Master consulta auditoria" on public.audit_events;
create policy "Somente Master consulta auditoria"
on public.audit_events for select to authenticated
using (public.is_master());

drop policy if exists "Nenhum usuário insere auditoria diretamente" on public.audit_events;
create policy "Nenhum usuário insere auditoria diretamente"
on public.audit_events for insert to authenticated
with check (false);

create or replace function public.write_audit_event(
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_company_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_actor_id uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_events(event_type, entity_type, entity_id, company_id, actor_id, metadata)
  values (p_event_type, p_entity_type, p_entity_id, p_company_id, p_actor_id, coalesce(p_metadata, '{}'::jsonb));
end;
$$;

create or replace function public.audit_asset_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid;
  kind text;
  details jsonb;
begin
  company := coalesce(new.current_company_id, new.company_id, old.current_company_id, old.company_id);
  if tg_op = 'INSERT' then
    perform public.write_audit_event('CADASTRO', 'ATIVO', new.id, company, jsonb_build_object('name', new.name, 'status', new.status));
    return new;
  end if;
  if old.current_company_id is distinct from new.current_company_id or old.company_id is distinct from new.company_id then
    kind := 'TRANSFERENCIA';
  elsif old.lifecycle_status is distinct from new.lifecycle_status then
    kind := case new.lifecycle_status when 'VENDIDO' then 'VENDA' when 'BAIXADO' then 'BAIXA' else 'CICLO_DE_VIDA' end;
  elsif old.classification_status is distinct from new.classification_status or old.company_id is distinct from new.company_id then
    kind := 'RECLASSIFICACAO';
  else
    kind := 'ALTERACAO';
  end if;
  details := jsonb_build_object('name', new.name, 'before', jsonb_build_object('company_id', old.company_id, 'status', old.status, 'lifecycle_status', old.lifecycle_status, 'classification_status', old.classification_status), 'after', jsonb_build_object('company_id', new.company_id, 'status', new.status, 'lifecycle_status', new.lifecycle_status, 'classification_status', new.classification_status));
  perform public.write_audit_event(kind, 'ATIVO', new.id, company, details);
  return new;
end;
$$;

drop trigger if exists audit_assets_change on public.assets;
create trigger audit_assets_change
after insert or update on public.assets
for each row execute function public.audit_asset_change();

create or replace function public.audit_document_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.write_audit_event(case when tg_op = 'INSERT' then 'DOCUMENTO_ADICIONADO' else 'DOCUMENTO_ALTERADO' end, 'DOCUMENTO', new.id, new.company_id, jsonb_build_object('asset_id', new.asset_id, 'file_name', new.file_name, 'document_type', new.document_type));
  return new;
end;
$$;

drop trigger if exists audit_asset_documents_change on public.asset_documents;
create trigger audit_asset_documents_change
after insert or update on public.asset_documents
for each row execute function public.audit_document_change();

revoke all on function public.write_audit_event(text, text, uuid, uuid, jsonb, uuid) from public;


-- ===== FIM: supabase\audit-monitor-migration.sql =====

-- ===== INÍCIO: supabase\apply-storage-isolation.sql =====

-- AtivoFrota — correção de isolamento do Storage
-- Execute no SQL Editor somente após confirmar que public.profiles,
-- public.assets e public.user_companies estão presentes.
-- Esta migração substitui políticas bucket-wide por autorização por ativo/empresa.

begin;

create or replace function public.can_access_asset_storage(path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  asset_uuid uuid;
begin
  if public.is_master() then
    return true;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active = true
  ) then
    return false;
  end if;

  if path !~ '^assets/[0-9a-fA-F-]{36}/(documents|photos)/' then
    return false;
  end if;

  begin
    asset_uuid := split_part(path, '/', 2)::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  return exists (
    select 1
    from public.assets a
    join public.user_companies uc
      on uc.company_id = coalesce(a.current_company_id, a.company_id)
     and uc.user_id = auth.uid()
    where a.id = asset_uuid
  );
end;
$$;

revoke all on function public.can_access_asset_storage(text) from public;
grant execute on function public.can_access_asset_storage(text) to authenticated;

drop policy if exists "Usuários autenticados enviam documentos" on storage.objects;
drop policy if exists "Usuários autenticados leem documentos" on storage.objects;
drop policy if exists "Usuários autenticados podem atualizar documentos" on storage.objects;
drop policy if exists "Usuários autenticados podem enviar documentos" on storage.objects;
drop policy if exists "Usuários autenticados podem visualizar documentos" on storage.objects;
drop policy if exists "Usuários autorizados leem documentos" on storage.objects;
drop policy if exists "Usuários autorizados enviam documentos" on storage.objects;
drop policy if exists "Usuários autorizados atualizam documentos" on storage.objects;

create policy "Usuários autorizados leem documentos"
on storage.objects for select to authenticated
using (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (
      name like 'imports/%'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.active = true
      )
    )
  )
);

create policy "Usuários autorizados enviam documentos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (
      name like 'imports/%'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.active = true
      )
    )
  )
);

create policy "Usuários autorizados atualizam documentos"
on storage.objects for update to authenticated
using (
  bucket_id = 'ativos-documentos'
  and public.can_access_asset_storage(name)
)
with check (
  bucket_id = 'ativos-documentos'
  and public.can_access_asset_storage(name)
);

commit;

-- Verificação pós-aplicação:
select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
order by policyname;


-- ===== FIM: supabase\apply-storage-isolation.sql =====

-- ===== INÍCIO: supabase\cleanup-legacy-rls.sql =====

-- AtivoFrota — limpeza de políticas RLS legadas
-- Execute depois das políticas finais de profiles, assets, documentos e auditoria.
-- A combinação de políticas permissivas no PostgreSQL é OR; políticas antigas
-- podem ampliar o acesso mesmo quando uma política nova está correta.

begin;

-- Profiles: manter somente as políticas finais.
drop policy if exists "Usuário pode atualizar o próprio perfil" on public.profiles;
drop policy if exists "Usuário pode visualizar o próprio perfil" on public.profiles;

-- Companies: remover leitura legada que pode ignorar o estado ativo.
drop policy if exists "Usuários autenticados podem visualizar empresas" on public.companies;

-- Vínculos: manter somente consulta própria/Master.
drop policy if exists "Usuário pode visualizar suas empresas" on public.user_companies;

-- Assets: remover políticas legadas substituídas pelo RLS master/patrimonial.
drop policy if exists "Usuários podem atualizar ativos de suas empresas" on public.assets;
drop policy if exists "Usuários podem criar ativos em suas empresas" on public.assets;
drop policy if exists "Usuários podem visualizar ativos de suas empresas" on public.assets;

-- Documents: remover políticas legadas substituídas pela autorização por ativo/empresa.
drop policy if exists "Usuários podem adicionar documentos de suas empresas" on public.asset_documents;
drop policy if exists "Usuários podem atualizar documentos de suas empresas" on public.asset_documents;
drop policy if exists "Usuários podem visualizar documentos de suas empresas" on public.asset_documents;

-- Histórico: somente triggers SECURITY DEFINER devem inserir eventos.
drop policy if exists "Usuários autenticados registram histórico de ativos" on public.asset_events;
drop policy if exists "Usuários autenticados consultam histórico de ativos" on public.asset_events;
drop policy if exists "Usuários autorizados consultam histórico de ativos" on public.asset_events;
create policy "Usuários autorizados consultam histórico de ativos"
on public.asset_events for select to authenticated
using (
  public.is_master()
  or exists (
    select 1
    from public.assets a
    join public.user_companies uc
      on uc.user_id = auth.uid()
     and uc.company_id = coalesce(a.current_company_id, a.company_id)
    where a.id = asset_events.asset_id
  )
);

commit;

-- Verificação: as políticas legadas acima não devem retornar linhas.
select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and policyname in (
    'Usuário pode atualizar o próprio perfil',
    'Usuário pode visualizar o próprio perfil',
    'Usuários autenticados podem visualizar empresas',
    'Usuário pode visualizar suas empresas',
    'Usuários podem atualizar ativos de suas empresas',
    'Usuários podem criar ativos em suas empresas',
    'Usuários podem visualizar ativos de suas empresas',
    'Usuários podem adicionar documentos de suas empresas',
    'Usuários podem atualizar documentos de suas empresas',
    'Usuários podem visualizar documentos de suas empresas',
    'Usuários autenticados registram histórico de ativos',
    'Usuários autenticados consultam histórico de ativos'
  );


-- ===== FIM: supabase\cleanup-legacy-rls.sql =====
