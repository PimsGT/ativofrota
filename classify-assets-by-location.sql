-- NÃO EXECUTAR: rascunho descontinuado.
-- operational_location é apenas o local de uso, não o proprietário.
-- A classificação patrimonial deve usar a razão social/proprietário.

update public.assets a
set
  company_id = c.id,
  raw_company_name = coalesce(nullif(a.raw_company_name, ''), trim(a.operational_location)),
  classification_status = 'classificado',
  updated_at = now()
from public.companies c
where a.classification_status <> 'classificado'
  and upper(trim(a.operational_location)) = upper(trim(c.name))
  and c.name in ('AGRO IPUÃ', 'SANTA MARIA', 'SERRA BRANCA');

select
  count(*) as total,
  count(*) filter (where classification_status = 'classificado') as classificados,
  count(*) filter (where classification_status in ('pendente', 'revisar')) as pendentes
from public.assets;

select
  classification_status,
  operational_location,
  raw_company_name,
  count(*) as quantidade
from public.assets
where classification_status <> 'classificado'
group by classification_status, operational_location, raw_company_name
order by quantidade desc;
