-- AtivoFrota: transformar uma conta Auth existente em Master.
-- Execute no Supabase SQL Editor depois de executar supabase-user-access.sql.
-- Este script não altera a senha da conta.

insert into public.profiles (id, display_name, role, must_change_password, active)
select
  id,
  coalesce(raw_user_meta_data ->> 'display_name', 'PIMS - Master'),
  'master',
  false,
  true
from auth.users
where lower(email) = lower('pims@olvego.com.br')
on conflict (id) do update
set
  display_name = excluded.display_name,
  role = 'master',
  must_change_password = false,
  active = true,
  updated_at = timezone('utc', now());

-- Confirmação: deve retornar exatamente uma linha.
select p.id, p.display_name, p.role, p.must_change_password, p.active
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = lower('pims@olvego.com.br');
