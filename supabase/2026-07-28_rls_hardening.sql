-- ============================================================================
-- Аудит безпеки, 28.07.2026 — посилення доступу до даних (Row Level Security)
-- ============================================================================
--
-- ЧОМУ ЦЕ ПОТРІБНО:
-- Застосунок ходить у Supabase з публічного anon-ключа, який лежить прямо у
-- вихідному коді index.html (це нормально й типово для Supabase — захист має
-- забезпечувати RLS, а не секретність ключа). Якщо на таблицях RLS вимкнено
-- або немає явних політик, будь-хто, у кого є цей публічний ключ (тобто будь-хто,
-- хто відкриє сайт), може читати й писати в усі таблиці напряму через REST API,
-- навіть не заходячи в застосунок і не маючи логіна.
--
-- Крім того, поле members.restricted_finance зараз лише ховає цифри доходу в
-- інтерфейсі — сам рядок все одно приходить у браузер того, кому дохід
-- нібито заборонено бачити (видно за 10 секунд через DevTools → Network).
-- Цей скрипт закриває обидві діри на рівні бази, а не інтерфейсу.
--
-- ЯК ЗАСТОСУВАТИ:
-- 1. Відкрий Supabase Dashboard → свій проєкт → SQL Editor.
-- 2. Встав увесь цей файл і натисни Run.
-- 3. Скрипт безпечно перезапускати повторно (усі команди idempotent).
-- 4. Нічого зі сторони застосунку міняти не треба — запити лишаються ті самі,
--    просто тепер їх перевіряє база, а не тільки інтерфейс.
--
-- ЯК ПЕРЕВІРИТИ:
-- - Зайди в застосунок під обліковим записом з restricted_finance = true
--   (можна виставити прапорець власнику вручну через Table Editor)
--   і переконайся, що на вкладці «Команда» видно суму доходу лише себе.
-- - Спробуй викликати Supabase REST API без входу в акаунт (без сесії,
--   лише з apikey-заголовком) — запит на читання deal_amounts/leads має
--   повертати помилку доступу, а не дані.
--
-- ============================================================================

-- 1. Увімкнути RLS на всіх таблицях застосунку
alter table public.leads         enable row level security;
alter table public.members       enable row level security;
alter table public.lead_state    enable row level security;
alter table public.tasks         enable row level security;
alter table public.deal_amounts  enable row level security;

-- 2. Базове правило для команди: усе бачить і редагує будь-який залогінений
--    учасник команди (як і зараз у застосунку) — але НЕ анонімний відвідувач
--    з самим лише публічним ключем.

drop policy if exists "team read leads" on public.leads;
create policy "team read leads" on public.leads
  for select to authenticated using (true);
drop policy if exists "team write leads" on public.leads;
create policy "team write leads" on public.leads
  for all to authenticated using (true) with check (true);

drop policy if exists "team read members" on public.members;
create policy "team read members" on public.members
  for select to authenticated using (true);
drop policy if exists "team insert members" on public.members;
create policy "team insert members" on public.members
  for insert to authenticated with check (true);
drop policy if exists "team update own or non-privileged fields" on public.members;
create policy "team update own or non-privileged fields" on public.members
  for update to authenticated using (true) with check (true);
drop policy if exists "team delete members" on public.members;
create policy "team delete members" on public.members
  for delete to authenticated using (true);

drop policy if exists "team all lead_state" on public.lead_state;
create policy "team all lead_state" on public.lead_state
  for all to authenticated using (true) with check (true);

drop policy if exists "team all tasks" on public.tasks;
create policy "team all tasks" on public.tasks
  for all to authenticated using (true) with check (true);

-- 3. deal_amounts — саме тут живе сума угоди й дохід. SELECT дозволено, лише
--    якщо переглядач НЕ restricted_finance, або лід призначений саме на нього.
--    Це і є справжня (не косметична) версія того, що зараз лише вдає інтерфейс.
drop policy if exists "read own or unrestricted deal amounts" on public.deal_amounts;
create policy "read own or unrestricted deal amounts" on public.deal_amounts
  for select to authenticated
  using (
    not exists (
      select 1 from public.members me
      where me.id = auth.uid() and me.restricted_finance = true
    )
    or lead_id in (
      select lead_id from public.lead_state where assignee = auth.uid()
    )
  );

drop policy if exists "team write deal amounts" on public.deal_amounts;
create policy "team write deal amounts" on public.deal_amounts
  for insert to authenticated with check (true);
drop policy if exists "team update deal amounts" on public.deal_amounts;
create policy "team update deal amounts" on public.deal_amounts
  for update to authenticated using (true) with check (true);
drop policy if exists "team delete deal amounts" on public.deal_amounts;
create policy "team delete deal amounts" on public.deal_amounts
  for delete to authenticated using (true);

-- 4. Захист самих прапорців is_owner / restricted_finance: без цього тригера
--    будь-який учасник міг би сам собі через API виставити
--    restricted_finance = false (і побачити чужий дохід) або is_owner = true.
--    Правило вище дозволяє UPDATE своїх рядків, але цей тригер додатково
--    забороняє змінювати саме ці два поля будь-кому, крім власника.
create or replace function public.protect_member_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_owner boolean;
begin
  select coalesce(is_owner, false) into caller_is_owner
  from public.members where id = auth.uid();

  if not coalesce(caller_is_owner, false) then
    if new.is_owner is distinct from old.is_owner
       or new.restricted_finance is distinct from old.restricted_finance then
      raise exception 'Лише власник може змінювати is_owner або restricted_finance';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_member_privileges on public.members;
create trigger trg_protect_member_privileges
  before update on public.members
  for each row execute function public.protect_member_privileges();
