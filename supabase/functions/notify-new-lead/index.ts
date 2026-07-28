// Викликається тригером public.notify_new_lead() (див. supabase/2026-07-29_telegram_notifications.sql)
// одразу після додавання нового ліда в таблицю leads. Шле повідомлення в командний Telegram.
//
// Деплой: supabase functions deploy notify-new-lead --no-verify-jwt
// (--no-verify-jwt — бо викликає це не залогінений користувач через Supabase Auth,
// а внутрішній тригер бази; захист від сторонніх викликів — через x-webhook-secret нижче.)
import { sendTelegram, escapeHtml, checkSharedSecret } from "../_shared/telegram.ts";

Deno.serve(async (req: Request) => {
  if (!checkSharedSecret(req)) return new Response("unauthorized", { status: 401 });

  const payload = await req.json().catch(() => null);
  const lead = payload?.record;
  if (!lead?.name) return new Response("ok: no record");

  const parts = [escapeHtml(lead.city), escapeHtml(lead.niche)].filter(Boolean);
  const text = `🆕 <b>Новий лід:</b> ${escapeHtml(lead.name)}` + (parts.length ? `\n${parts.join(" · ")}` : "");
  await sendTelegram(text);
  return new Response("ok");
});
