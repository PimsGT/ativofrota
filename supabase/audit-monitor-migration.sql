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
