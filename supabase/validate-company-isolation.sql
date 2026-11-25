-- AtivoFrota — validação somente leitura de isolamento entre empresas
-- Execute no Supabase SQL Editor.
-- Este arquivo não cria, atualiza ou remove dados permanentes.
-- Execute cada bloco separadamente se o SQL Editor não aceitar o arquivo inteiro.

-- 1) Tabelas e colunas essenciais.
select table_name,
       exists (
         select 1
         from information_schema.tables t2
         where t2.table_schema = 'public'
           and t2.table_name = t.table_name
       ) as table_exists
from (values
  ('profiles'),
  ('companies'),
  ('user_companies'),
  ('assets'),
  ('asset_documents'),
  ('asset_events'),
  ('audit_events')
) as t(table_name)
order by table_name;

select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'profiles' and column_name in ('id','role','active'))
    or (table_name = 'companies' and column_name in ('id','name'))
    or (table_name = 'user_companies' and column_name in ('user_id','company_id'))
    or (table_name = 'assets' and column_name in ('id','name','company_id','current_company_id'))
    or (table_name = 'asset_documents' and column_name in ('id','asset_id','company_id'))
  )
order by table_name, ordinal_position;

-- 2) RLS habilitado nas tabelas protegidas.
select n.nspname as schema_name,
       c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles','companies','user_companies','assets','asset_documents','asset_events','audit_events')
order by c.relname;

-- 3) Políticas atualmente instaladas.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public','storage')
  and tablename in ('profiles','companies','user_companies','assets','asset_documents','asset_events','audit_events','objects')
order by schemaname, tablename, policyname;

-- 4) Perfis, empresas e vínculos.
select p.id, p.display_name, p.role, p.active,
       count(uc.company_id) as linked_companies
from public.profiles p
left join public.user_companies uc on uc.user_id = p.id
 group by p.id, p.display_name, p.role, p.active
order by p.role, p.display_name;

select c.id, c.name, count(uc.user_id) as linked_users
from public.companies c
left join public.user_companies uc on uc.company_id = c.id
 group by c.id, c.name
order by c.name;

-- 5) Inconsistências de vínculos e ativos.
select 'orphan_user_company_user' as check_name, count(*) as total
from public.user_companies uc
left join public.profiles p on p.id = uc.user_id
where p.id is null
union all
select 'orphan_user_company_company', count(*)
from public.user_companies uc
left join public.companies c on c.id = uc.company_id
where c.id is null
union all
select 'asset_without_company', count(*)
from public.assets
where company_id is null and current_company_id is null
union all
select 'asset_company_mismatch', count(*)
from public.assets a
where a.company_id is not null
  and a.current_company_id is not null
  and a.company_id <> a.current_company_id
union all
select 'document_orphan_asset', count(*)
from public.asset_documents d
left join public.assets a on a.id = d.asset_id
where d.asset_id is not null and a.id is null;

-- 6) Distribuição dos ativos por empresa atual.
select coalesce(a.current_company_id, a.company_id) as effective_company_id,
       c.name as company_name,
       count(*) as asset_count
from public.assets a
left join public.companies c
  on c.id = coalesce(a.current_company_id, a.company_id)
group by coalesce(a.current_company_id, a.company_id), c.name
order by c.name nulls first;

-- 7) Teste operacional para um usuário Patrimonial.
-- Substitua os UUIDs abaixo por valores reais obtidos nos blocos 4 e 6.
-- Rode cada caso em uma execução separada no SQL Editor.
-- O resultado esperado é: somente ativos da empresa vinculada ao usuário.
-- A sessão do SQL Editor pode não permitir SET ROLE; nesse caso, use o teste E2E do app.

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'UUID_DO_USUARIO_PATRIMONIAL', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select a.id, a.name,
       coalesce(a.current_company_id, a.company_id) as effective_company_id,
       c.name as company_name
from public.assets a
left join public.companies c
  on c.id = coalesce(a.current_company_id, a.company_id)
order by c.name, a.name;

rollback;

-- 8) Teste negativo recomendado.
-- Escolha um asset_id pertencente a uma empresa NÃO vinculada ao usuário Patrimonial.
-- Com a sessão autenticada desse usuário, esta consulta deve retornar zero linhas:
-- select id, name, company_id, current_company_id
-- from public.assets
-- where id = 'UUID_DO_ATIVO_DE_OUTRA_EMPRESA';

-- 9) Teste de Storage.
-- Com a sessão autenticada do usuário Patrimonial, o download/listagem de um caminho
-- assets/<UUID_DE_ATIVO_DA_EMPRESA_NAO_AUTORIZADA>/documents/... deve falhar.
-- O mesmo teste para um ativo da empresa autorizada deve funcionar.
-- Não use service_role nesses testes, pois ela ignora RLS.
