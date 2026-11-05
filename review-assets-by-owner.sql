-- Revisão de proprietário: não usar operational_location para classificar empresa.
-- A empresa deve ser definida pela razão social/proprietário.

select
  classification_status,
  nullif(trim(raw_company_name), '') as razao_social,
  count(*) as quantidade,
  count(*) filter (where nullif(trim(chassis), '') is not null) as com_chassi,
  count(*) filter (where nullif(trim(operational_location), '') is not null) as com_local
from public.assets
where classification_status <> 'classificado'
group by classification_status, nullif(trim(raw_company_name), '')
order by quantidade desc, razao_social;

select
  a.legacy_id,
  a.name,
  a.raw_company_name as razao_social,
  a.chassis,
  a.operational_location as local_de_uso,
  i.nf_number
from public.assets a
left join public.assets_import i on i.legacy_id = a.legacy_id
where a.classification_status <> 'classificado'
order by a.raw_company_name nulls first, a.name;
