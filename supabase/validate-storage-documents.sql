-- AtivoFrota — validação de Storage e documentos
-- Somente leitura: não cria, altera ou remove dados.
-- Execute no Supabase SQL Editor.

-- 1) Bucket privado esperado.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'ativos-documentos' or name = 'ativos-documentos';

-- 2) Políticas atuais do Storage.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
order by policyname;

-- 3) Função de autorização esperada.
select n.nspname as schema_name,
       p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as returns,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'can_access_asset_storage';

-- 4) Documentos por empresa efetiva.
select coalesce(d.company_id, a.current_company_id, a.company_id) as effective_company_id,
       c.name as company_name,
       count(*) as document_count
from public.asset_documents d
left join public.assets a on a.id = d.asset_id
left join public.companies c
  on c.id = coalesce(d.company_id, a.current_company_id, a.company_id)
group by coalesce(d.company_id, a.current_company_id, a.company_id), c.name
order by c.name nulls first;

-- 5) Inconsistências de documentos.
select 'document_without_asset_and_company' as check_name, count(*) as total
from public.asset_documents
where asset_id is null and company_id is null
union all
select 'document_with_missing_asset', count(*)
from public.asset_documents d
left join public.assets a on a.id = d.asset_id
where d.asset_id is not null and a.id is null
union all
select 'document_company_differs_from_asset', count(*)
from public.asset_documents d
join public.assets a on a.id = d.asset_id
where d.company_id is not null
  and coalesce(a.current_company_id, a.company_id) is not null
  and d.company_id <> coalesce(a.current_company_id, a.company_id);

-- 6) Se existir uma coluna storage_path/path, localize registros fora do padrão.
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'asset_documents'
  and column_name in ('storage_path','path','file_path','object_path');

-- 7) Teste manual obrigatório com sessão real do aplicativo.
-- Não use service_role.
-- A) Patrimonial autorizado: abrir/baixar documento de ativo da sua empresa -> deve funcionar.
-- B) Patrimonial não autorizado: abrir/baixar documento de outra empresa -> deve falhar.
-- C) Caminho imports/ com usuário ativo -> somente se o fluxo de importação estiver autorizado.
-- D) Usuário desativado ou anônimo -> deve falhar.
-- O teste deve ser feito pelo app, usando a sessão real do usuário, pois o SQL Editor
-- normalmente executa como postgres e não representa um usuário submetido ao RLS.
