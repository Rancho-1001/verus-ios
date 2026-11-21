// Generates the app icon.
//
//     node scripts/make-icon.mjs
//
// The icon is the design law as a picture: a scatter of daily weigh-ins with
// one calm line cutting through them. Noise, and the truth inside it. No
// text — iOS icons are read at 60 points and a word is unreadable there.
//
// Colours are Nyansapo Labs': deep green and gold, so the product sits beside
// the company rather than apart from it.
//
// Requires sharp. The website project already depends on it, so this borrows
// that install rather than adding one here for a file regenerated twice a year.

import { writeFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(here, "..", "..", "nyansapo-labs-site", "package.json"));
const sharp = require("sharp");

const SIZE = 1024;
const OUT = join(here, "..", "Resources", "Assets.xcassets", "AppIcon.appiconset");

const green = "#1f5f4a";
const greenDeep = "#133a2d";
const cream = "#faf6f0";
const gold = "#e0b354";

/** The trend line: a gentle fall, left to right, with a slight easing. */
function trendPoints(count) {
  return Array.from({ length: count }, (_, i) => {
    const t = i / (count - 1);
    return {
      x: 170 + t * 684,
      // Falls from 395 to 660, easing out so it flattens slightly — a real
      // loss curve decelerates, and a ruler-straight line would look like a
      // chart of nothing in particular.
      y: 395 + (1 - Math.pow(1 - t, 1.7)) * 265,
    };
  });
}

/** Daily readings scattered either side of the line. Fixed offsets, not
 *  random, so the icon is identical on every run. */
const scatter = [
  -48, 34, -62, 18, 55, -28, 41, -70, 22, 60, -35, 14, -52, 38, -20, 47,
];

const line = trendPoints(64);
const path = line
  .map((p, i) => `${i === 0 ? "M" : "L"}${p.x.toFixed(1)} ${p.y.toFixed(1)}`)
  .join(" ");

const dots = scatter
  .map((offset, i) => {
    const t = (i + 0.5) / scatter.length;
    const onLine = trendPoints(64)[Math.round(t * 63)];
    return `<circle cx="${onLine.x.toFixed(1)}" cy="${(onLine.y + offset).toFixed(1)}" r="15"
              fill="${cream}" opacity="0.34"/>`;
  })
  .join("\n    ");

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="${green}"/>
      <stop offset="1" stop-color="${greenDeep}"/>
    </linearGradient>
  </defs>

  <!-- Full bleed. iOS applies its own corner mask, so rounding here would
       show as a dark halo inside the real corners. -->
  <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>

  <!-- The goal: a quiet gold rule the trend is heading toward. -->
  <line x1="150" y1="742" x2="874" y2="742"
        stroke="${gold}" stroke-width="7" stroke-linecap="round"
        stroke-dasharray="26 30" opacity="0.65"/>

  <!-- Daily noise. -->
  ${dots}

  <!-- The trend. Thick, calm, and the only thing in full strength. -->
  <path d="${path}" fill="none" stroke="${cream}"
        stroke-width="54" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;

await mkdir(OUT, { recursive: true });

const png = await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
await writeFile(join(OUT, "icon-1024.png"), png);

// One 1024 source; Xcode derives every other size from it.
await writeFile(
  join(OUT, "Contents.json"),
  JSON.stringify(
    {
      images: [{ filename: "icon-1024.png", idiom: "universal", platform: "ios", size: "1024x1024" }],
      info: { author: "xcode", version: 1 },
    },
    null,
    2
  ) + "\n"
);

console.log(`AppIcon written — ${SIZE}×${SIZE}, ${(png.length / 1024).toFixed(1)} kB`);
