// Швидка перевірка: чи весь inline JS у index.html хоча б синтаксично коректний.
// Не виконує код (тут немає DOM/Supabase) — лише компілює, щоб зловити банальні
// помилки (незакриту дужку, зайву кому тощо) ще до того, як хтось відкриє сайт.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const file = path.join(__dirname, "..", "index.html");
const html = fs.readFileSync(file, "utf8");

const scriptBlocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(
  (m) => m[1],
);

if (scriptBlocks.length === 0) {
  console.error("Не знайдено жодного inline <script> в index.html — перевір регулярку.");
  process.exit(1);
}

let ok = true;
scriptBlocks.forEach((code, i) => {
  try {
    new vm.Script(code, { filename: `index.html#inline-script-${i + 1}` });
  } catch (err) {
    ok = false;
    console.error(`Синтаксична помилка в inline-скрипті #${i + 1}:`);
    console.error(err.message);
  }
});

if (!ok) {
  process.exit(1);
}
console.log(`OK: ${scriptBlocks.length} inline-скрипт(и) в index.html синтаксично коректні.`);
