-- Relatório de revisão inicial de categorias.
-- Somente consulta; não altera ativos nem categorias.

-- 1. Categorias reais e quantidade de ativos.
select trim(category) as category, count(*) as asset_count
from public.assets
where category is not null and trim(category) <> ''
group by trim(category)
order by lower(trim(category));

-- 2. Agrupamento por forma normalizada (acentos, pontuação e espaços).
with normalized as (
  select
    trim(category) as category,
    regexp_replace(
      upper(translate(trim(category), 'ÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC')),
      '[^A-Z0-9]+', '', 'g'
    ) as normalized_category,
    count(*) as asset_count
  from public.assets
  where category is not null and trim(category) <> ''
  group by trim(category)
)
select normalized_category, string_agg(category, ' | ' order by category) as variants, sum(asset_count) as asset_count
from normalized
group by normalized_category
having count(*) > 1
order by normalized_category;

-- 3. Candidata encontrada no arquivo de importação local:
-- TRAT. SEMENTE -> TRATAMENTO DE SEMENTE
-- A migração deve ser confirmada pelo Master no painel usando Mesclar categorias.
