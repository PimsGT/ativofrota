-- AtivoFrota: perfis e primeiro acesso
-- Execute no Supabase SQL Editor antes de usar a tela Administração > Usuários.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('master', 'patrimonial')),
  must_change_password boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

-- Compatibilidade com uma tabela profiles criada antes desta migração.
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists role text;
alter table public.profiles add column if not exists must_change_password boolean not null default true;
alter table public.profiles add column if not exists active boolean not null default true;
alter table public.profiles add column if not exists created_at timestamptz not null default timezone('utc', now());
alter table public.profiles add column if not exists updated_at timestamptz not null default timezone('utc', now());

update public.profiles
set display_name = coalesce(nullif(display_name, ''), 'Usuário AtivoFrota'),
    role = case when role in ('master', 'patrimonial') then role else 'patrimonial' end,
    must_change_password = coalesce(must_change_password, true),
    active = coalesce(active, true)
where display_name is null
   or display_name = ''
   or role is null
   or role not in ('master', 'patrimonial')
   or must_change_password is null
   or active is null;

alter table public.profiles alter column display_name set not null;
alter table public.profiles alter column role set not null;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('master', 'patrimonial'));

create index if not exists profiles_role_idx on public.profiles(role);

alter table public.profiles enable row level security;

create or replace function public.is_master()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'master' and active = true
  );
$$;

revoke all on function public.is_master() from public;
grant execute on function public.is_master() to authenticated;

drop policy if exists "profiles_select_self_or_master" on public.profiles;
create policy "profiles_select_self_or_master"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_master());

drop policy if exists "profiles_insert_master" on public.profiles;
create policy "profiles_insert_master"
on public.profiles for insert to authenticated
with check (public.is_master());

drop policy if exists "profiles_update_self_password_or_master" on public.profiles;
create policy "profiles_update_self_password_or_master"
on public.profiles for update to authenticated
using (id = auth.uid() or public.is_master())
with check (
  public.is_master()
  or (
    id = auth.uid()
    and role = (select p.role from public.profiles p where p.id = auth.uid())
    and active = (select p.active from public.profiles p where p.id = auth.uid())
    and must_change_password = false
  )
);

create or replace function public.set_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_profile_updated_at();

-- Depois de executar este arquivo, cadastre manualmente o primeiro master:
-- insert into public.profiles (id, display_name, role, must_change_password)
-- values ('UUID_DO_USUARIO_AUTH', 'Leonardo Aguiar', 'master', false);
