// Спільний хелпер для відправки повідомлень у Telegram.
// Токен бота НІКОЛИ не читається з коду — тільки з секрету середовища
// TELEGRAM_BOT_TOKEN, який ти встановлюєш окремо (Supabase Dashboard →
// Edge Functions → Secrets). У репозиторії його немає і не повинно бути.

export function escapeHtml(s: string | null | undefined): string {
  return (s ?? "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] as string));
}

export async function sendTelegram(text: string): Promise<void> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const chatId = Deno.env.get("TELEGRAM_CHAT_ID");
  if (!token || !chatId) {
    console.error("Немає TELEGRAM_BOT_TOKEN або TELEGRAM_CHAT_ID у секретах функції — повідомлення не надіслано.");
    return;
  }
  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text, parse_mode: "HTML", disable_web_page_preview: true }),
  });
  if (!res.ok) console.error("Telegram sendMessage failed:", await res.text());
}

export function checkSharedSecret(req: Request): boolean {
  const expected = Deno.env.get("FUNCTIONS_SHARED_SECRET");
  const got = req.headers.get("x-webhook-secret");
  return !!expected && got === expected;
}
