-- AtivoFrota — endurecimento para produção
-- Execute após supabase-user-access.sql, assets-rls-master-access.sql e asset-lifecycle-migration.sql.

-- Usuário comum não pode alterar identidade, perfil, status ou liberar a troca de senha.
drop policy if exists "profiles_update_self_password_or_master" on public.profiles;
create policy "profiles_update_self_password_or_master"
on public.profiles for update to authenticated
using (id = auth.uid() or public.is_master())
with check (
  public.is_master()
  or (
    id = auth.uid()
    and display_name = (select p.display_name from public.profiles p where p.id = auth.uid())
    and role = (select p.role from public.profiles p where p.id = auth.uid())
    and active = (select p.active from public.profiles p where p.id = auth.uid())
    and must_change_password = false
  )
);

-- Operadores não podem devolver ativos classificados para o conjunto aberto.
drop policy if exists "Operadores corrigem ativos sem classificação" on public.assets;
create policy "Operadores corrigem ativos sem classificação"
on public.assets for update to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true and p.role in ('master','patrimonial'))
  and (
    company_id is null
    or exists (select 1 from public.user_companies uc where uc.user_id = auth.uid() and uc.company_id = public.assets.company_id)
  )
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true and p.role in ('master','patrimonial'))
  and company_id is not null
  and (
    public.is_master()
    or exists (select 1 from public.user_companies uc where uc.user_id = auth.uid() and uc.company_id = public.assets.company_id)
  )
);

-- Empresas e vínculos: leitura para usuários ativos; manutenção somente pelo Master.
alter table public.companies enable row level security;
drop policy if exists "Usuários ativos consultam empresas" on public.companies;
create policy "Usuários ativos consultam empresas" on public.companies for select to authenticated using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true));
drop policy if exists "Master gerencia empresas" on public.companies;
create policy "Master gerencia empresas" on public.companies for all to authenticated using (public.is_master()) with check (public.is_master());

alter table public.user_companies enable row level security;
drop policy if exists "Usuário consulta seus vínculos" on public.user_companies;
create policy "Usuário consulta seus vínculos" on public.user_companies for select to authenticated using (user_id = auth.uid() or public.is_master());
drop policy if exists "Master gerencia vínculos" on public.user_companies;
create policy "Master gerencia vínculos" on public.user_companies for all to authenticated using (public.is_master()) with check (public.is_master());

-- Documentos: usuário ativo consulta; inclusão depende do acesso ao ativo ou de ser Master.
alter table public.asset_documents enable row level security;
drop policy if exists "Usuários consultam documentos autorizados" on public.asset_documents;
create policy "Usuários consultam documentos autorizados" on public.asset_documents for select to authenticated using (public.is_master() or exists (select 1 from public.assets a where a.id = asset_documents.asset_id));
drop policy if exists "Usuários inserem documentos autorizados" on public.asset_documents;
create policy "Usuários inserem documentos autorizados"
on public.asset_documents for insert to authenticated
with check (
  public.is_master()
  or (
    asset_documents.asset_id is not null
    and exists (select 1 from public.assets a where a.id = asset_documents.asset_id)
  )
  or (
    asset_documents.asset_id is null
    and exists (
      select 1
      from public.user_companies uc
      where uc.user_id = auth.uid()
        and uc.company_id = asset_documents.company_id
    )
  )
);

drop policy if exists "Usuários removem documentos autorizados" on public.asset_documents;
create policy "Usuários removem documentos autorizados"
on public.asset_documents for delete to authenticated
using (
  public.is_master()
  or exists (
    select 1
    from public.assets a
    join public.user_companies uc
      on uc.company_id = coalesce(a.current_company_id, a.company_id)
     and uc.user_id = auth.uid()
    where a.id = asset_documents.asset_id
  )
);

-- Bucket privado: os arquivos só devem ser acessados por URLs assinadas emitidas pelo app.
insert into storage.buckets (id, name, public) values ('ativos-documentos', 'ativos-documentos', false) on conflict (id) do update set public = false;

create or replace function public.can_access_asset_storage(path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  asset_uuid uuid;
begin
  if public.is_master() then
    return true;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.active = true
  ) then
    return false;
  end if;

  if path !~ '^assets/[0-9a-fA-F-]{36}/(documents|photos)/' then
    return false;
  end if;

  begin
    asset_uuid := split_part(path, '/', 2)::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  return exists (
    select 1
    from public.assets a
    join public.user_companies uc
      on uc.company_id = coalesce(a.current_company_id, a.company_id)
     and uc.user_id = auth.uid()
    where a.id = asset_uuid
  );
end;
$$;

revoke all on function public.can_access_asset_storage(text) from public;
grant execute on function public.can_access_asset_storage(text) to authenticated;

drop policy if exists "Usuários autenticados leem documentos" on storage.objects;
drop policy if exists "Usuários autorizados leem documentos" on storage.objects;
create policy "Usuários autorizados leem documentos"
on storage.objects for select to authenticated
using (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (name like 'imports/%' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true))
  )
);

drop policy if exists "Usuários autenticados enviam documentos" on storage.objects;
drop policy if exists "Usuários autorizados enviam documentos" on storage.objects;
create policy "Usuários autorizados enviam documentos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (name like 'imports/%' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.active = true))
  )
);

drop policy if exists "Usuários autorizados removem documentos" on storage.objects;
create policy "Usuários autorizados removem documentos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'ativos-documentos'
  and public.can_access_asset_storage(name)
);

-- O app trabalha com o tamanho máximo de 25 MB; a validação também deve ser mantida no bucket/proxy escolhido.
