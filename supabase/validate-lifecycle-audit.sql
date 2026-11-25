-- AtivoFrota — validação de ciclo de vida e auditoria
-- Somente leitura: não altera ativos nem eventos.
-- Execute no Supabase SQL Editor.

-- 1) Tabelas e colunas de histórico.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('asset_events','audit_events')
order by table_name, ordinal_position;

-- 2) RLS e políticas do histórico.
select n.nspname as schema_name,
       c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('asset_events','audit_events')
order by c.relname;

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('asset_events','audit_events')
order by tablename, policyname;

-- 3) Triggers instalados em ativos.
select n.nspname as schema_name,
       c.relname as table_name,
       t.tgname as trigger_name,
       pg_get_triggerdef(t.oid) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal
  and n.nspname = 'public'
  and c.relname in ('assets','asset_documents')
order by c.relname, t.tgname;

-- 4) Histórico existente por tipo.
select event_type, count(*) as total
from public.asset_events
 group by event_type
order by event_type;

select event_type, count(*) as total
from public.audit_events
 group by event_type
order by event_type;

-- 5) Transferências com origem/destino disponíveis no payload, quando existirem.
select e.id, e.asset_id, e.event_type, e.created_at,
       to_jsonb(e) as event_data
from public.asset_events e
where event_type = 'TRANSFERENCIA'
order by created_at desc
limit 50;

-- 6) Inconsistências básicas do histórico.
select 'events_without_asset' as check_name, count(*) as total
from public.asset_events e
left join public.assets a on a.id = e.asset_id
where a.id is null
union all
select 'audit_asset_events_without_asset', count(*)
from public.audit_events e
left join public.assets a on a.id = e.entity_id
where e.entity_type = 'ATIVO' and a.id is null
union all
select 'audit_events_without_actor', count(*)
from public.audit_events
where actor_id is null;

-- 7) Testes funcionais devem ser executados no app com um ativo de homologação:
-- A) transferir empresa A -> B: esperar TRANSFERENCIA em asset_events e audit_events;
-- B) marcar VENDIDO: esperar VENDA;
-- C) marcar BAIXADO: esperar BAIXA;
-- D) atualizar campo sem ciclo de vida: esperar ALTERACAO/RECLASSIFICACAO conforme regra;
-- E) consultar Auditoria como Master: permitido;
-- F) consultar Auditoria como Patrimonial: negado.
