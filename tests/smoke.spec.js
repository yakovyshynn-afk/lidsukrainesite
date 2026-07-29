// Димовий тест: відкриває index.html так само, як реальний браузер, і перевіряє,
// що застосунок не падає з JS-помилкою і показує форму входу (CLOUD-режим тут
// завжди увімкнений, тож без реальної сесії має бути видно #authScreen, а не
// впасти в білий екран). Не логінимось насправді — це лише перевірка, що зміни
// в index.html нікого не зламали, а не тест бізнес-логіки.
//
// Застереження: сторінка тягне supabase-js з CDN і звертається до реального
// Supabase-проєкту за сесією (без даних — просто "чи є активна сесія"), тож
// тест потребує мережі й може зрідка бути нестабільним, якщо CDN/проєкт лежить.
const { test, expect } = require("@playwright/test");
const path = require("path");

test("index.html вантажиться без консольних помилок і показує форму входу", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (err) => errors.push(String(err)));
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });

  const filePath = "file://" + path.join(__dirname, "..", "index.html");
  await page.goto(filePath);

  await expect(page.locator("#authScreen")).toBeVisible({ timeout: 15_000 });
  await expect(page.locator("#authEmail")).toBeVisible();
  await expect(page.locator("#appRoot")).toBeHidden();

  expect(errors, "консоль не повинна містити помилок при завантаженні: " + errors.join(" | ")).toEqual([]);
});
