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
