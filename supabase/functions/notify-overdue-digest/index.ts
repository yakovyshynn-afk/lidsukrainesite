// Викликається раз на день через pg_cron (див. supabase/2026-07-29_telegram_notifications.sql).
// Збирає всі активні ліди з простроченою чи взагалі не запланованою наступною дією
// і шле короткий дайджест у командний Telegram.
//
// Деплой: supabase functions deploy notify-overdue-digest --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendTelegram, escapeHtml, checkSharedSecret } from "../_shared/telegram.ts";

Deno.serve(async (req: Request) => {
  if (!checkSharedSecret(req)) return new Response("unauthorized", { status: 401 });

  // SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY підставляються Supabase автоматично
  // для кожної Edge Function — вручну їх задавати не треба.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const today = new Date().toISOString().slice(0, 10);
  const { data: states, error } = await supabase
    .from("lead_state")
    .select("lead_id, next_action, stage")
    .lt("next_action", today)
    .not("stage", "in", "(won,lost)");

  if (error) {
    console.error("Помилка запиту lead_state:", error.message);
    return new Response("error", { status: 500 });
  }
  if (!states || !states.length) return new Response("ok: none overdue");

  const ids = states.map((s) => s.lead_id);
  const { data: leads } = await supabase.from("leads").select("id,name").in("id", ids);
  const nameById = Object.fromEntries((leads ?? []).map((l) => [l.id, l.name]));

  const lines = states.slice(0, 20).map((s) => `• ${escapeHtml(nameById[s.lead_id] ?? s.lead_id)}`);
  const more = states.length > 20 ? `\n…і ще ${states.length - 20}` : "";
  const text = `⏰ <b>Прострочено сьогодні: ${states.length}</b>\n${lines.join("\n")}${more}`;

  await sendTelegram(text);
  return new Response("ok");
});
