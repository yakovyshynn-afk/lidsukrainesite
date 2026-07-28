-- ============================================================================
-- Telegram-сповіщення: нові ліди одразу, прострочені — щоденним дайджестом
-- ============================================================================
--
-- Цей файл НЕ містить жодних секретів (токен бота, chat_id, спільний секрет) —
-- лише placeholder-и, які ти сам замінюєш ПІД ЧАС виконання в SQL Editor.
-- Сам виконаний текст ніде не комітиться назад у репозиторій.
--
-- КРОК 1 — задеплой дві Edge Function з supabase/functions/:
--   supabase functions deploy notify-new-lead --no-verify-jwt
--   supabase functions deploy notify-overdue-digest --no-verify-jwt
--   (або через Dashboard → Edge Functions → Create Function → вставити код
--   з відповідного index.ts; вимкни "Enforce JWT verification" для обох)
--
-- КРОК 2 — постав секрети (Dashboard → Edge Functions → Manage secrets,
--   або `supabase secrets set ІМ'Я=значення`):
--   TELEGRAM_BOT_TOKEN        — токен від @BotFather
--   TELEGRAM_CHAT_ID          — id командного чату/групи (від'ємне число для груп;
--                               додай бота в групу, напиши будь-що, перешли те
--                               повідомлення @getidsbot — він покаже chat id)
--   FUNCTIONS_SHARED_SECRET   — будь-який довгий випадковий рядок, який ти
--                               придумаєш сам (напр. `openssl rand -hex 24`) —
--                               він захищає функції від чужих викликів ззовні
--
-- КРОК 3 — встав тут-таки нижче замість <FUNCTIONS_SHARED_SECRET> ТОЙ САМИЙ
--   рядок, що і в секреті функції, і замість <PROJECT_REF> — референс проєкту
--   (chnalwmtvbfvjtjullxm, він і так публічний — видно в SUPABASE_URL коду сайту).
--   Встав увесь скрипт у SQL Editor і натисни Run.
--
-- ============================================================================

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- 1. Миттєве сповіщення про новий лід — тригер на INSERT у leads.
create or replace function public.notify_new_lead()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/notify-new-lead',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '<FUNCTIONS_SHARED_SECRET>'
    ),
    body := jsonb_build_object('record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_new_lead on public.leads;
create trigger trg_notify_new_lead
  after insert on public.leads
  for each row execute function public.notify_new_lead();

-- 2. Щоденний дайджест прострочених лідів — pg_cron викликає функцію о 06:00 UTC
--    (це ≈ 09:00 за київським часом; зміни '0 6 * * *', якщо треба інакше).
select cron.schedule(
  'telegram-overdue-digest',
  '0 6 * * *',
  $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/notify-overdue-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '<FUNCTIONS_SHARED_SECRET>'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- Щоб зупинити щоденний дайджест пізніше:
-- select cron.unschedule('telegram-overdue-digest');
