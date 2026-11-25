-- AtivoFrota — correção de isolamento do Storage
-- Execute no SQL Editor somente após confirmar que public.profiles,
-- public.assets e public.user_companies estão presentes.
-- Esta migração substitui políticas bucket-wide por autorização por ativo/empresa.

begin;

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
    where p.id = auth.uid()
      and p.active = true
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

drop policy if exists "Usuários autenticados enviam documentos" on storage.objects;
drop policy if exists "Usuários autenticados leem documentos" on storage.objects;
drop policy if exists "Usuários autenticados podem atualizar documentos" on storage.objects;
drop policy if exists "Usuários autenticados podem enviar documentos" on storage.objects;
drop policy if exists "Usuários autenticados podem visualizar documentos" on storage.objects;
drop policy if exists "Usuários autorizados leem documentos" on storage.objects;
drop policy if exists "Usuários autorizados enviam documentos" on storage.objects;
drop policy if exists "Usuários autorizados atualizam documentos" on storage.objects;

create policy "Usuários autorizados leem documentos"
on storage.objects for select to authenticated
using (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (
      name like 'imports/%'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.active = true
      )
    )
  )
);

create policy "Usuários autorizados enviam documentos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'ativos-documentos'
  and (
    public.can_access_asset_storage(name)
    or (
      name like 'imports/%'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.active = true
      )
    )
  )
);

create policy "Usuários autorizados atualizam documentos"
on storage.objects for update to authenticated
using (
  bucket_id = 'ativos-documentos'
  and public.can_access_asset_storage(name)
)
with check (
  bucket_id = 'ativos-documentos'
  and public.can_access_asset_storage(name)
);

commit;

-- Verificação pós-aplicação:
select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
order by policyname;
