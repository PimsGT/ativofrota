insert into public.assets (legacy_id,name,company_id,category,brand,model,year,operational_location,chassis,status,raw_company_name,classification_status,created_at,updated_at)
select i.legacy_id,i.name,c.id,nullif(i.category,''),nullif(i.brand,''),nullif(i.model,''),case when i.year ~ '^[0-9]{4}$' then i.year::integer else null end,nullif(i.operational_location,''),nullif(i.chassis,''),'Pendente',nullif(i.company_name,''),case when c.id is not null then 'classificado' when nullif(i.company_name,'') is null then 'pendente' else 'revisar' end,now(),now()
from public.assets_import i
left join public.companies c on upper(trim(c.name))=upper(trim(i.company_name))
where not exists (select 1 from public.assets a where a.legacy_id=i.legacy_id);

select count(*) as total_importado,count(*) filter (where classification_status='classificado') as classificados,count(*) filter (where classification_status in ('pendente','revisar')) as para_revisao from public.assets;
select classification_status,raw_company_name,count(*) from public.assets where classification_status<>'classificado' group by classification_status,raw_company_name order by classification_status,count(*) desc;
