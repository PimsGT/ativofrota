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
