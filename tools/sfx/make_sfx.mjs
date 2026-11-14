// Generates the app's UI sounds with ElevenLabs sound effects → ios/Upscroll/Resources/sfx_<name>.mp3
// Usage: ELEVENLABS_API_KEY in the repo's .env.local (npx @elevenlabs/cli onboard) or .env, then: cd tools/sfx && npm install && npm run make
// Optional: `npm run make -- correct wrong` to (re)make only some sounds.
import { ElevenLabsClient } from '@elevenlabs/elevenlabs-js';
import { writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../ios/Upscroll/Resources');

// Short, cozy, game-like UI sounds that sit under speech (the app also plays them quietly).
export const SOUNDS = {
  correct:   { text: 'Bright cheerful two-note chime going up, success sound for a cute mobile learning game, clean, soft attack, no reverb tail', seconds: 0.8 },
  wrong:     { text: 'Clear short low wooden block knock, friendly wrong-answer buzzer for a mobile quiz game, audible and soft, not harsh', seconds: 0.6 },
  milestone: { text: 'Clear bright rising chime, three glockenspiel notes going up with a little sparkle, cheerful achievement notification, loud and present', seconds: 1.2 },
  unlock:    { text: 'Short magical level-up fanfare, bright bells and a shimmering swell, unlocking something new in a cozy mobile game', seconds: 2.0 },
  reward:    { text: 'Cute coin pickup with a little sparkle twinkle, collectible reward in a cozy mobile game, short', seconds: 0.9 },
  pop:       { text: 'Soft round bubble pop, subtle UI sound for a card appearing, quiet and clean', seconds: 0.5 },
};

const only = process.argv.slice(2);
if (!process.env.ELEVENLABS_API_KEY) {
  console.error('ELEVENLABS_API_KEY is not set (run npx @elevenlabs/cli onboard init, or add it to the repo .env.local).');
  process.exit(1);
}
const client = new ElevenLabsClient();
await mkdir(OUT, { recursive: true });

for (const [name, s] of Object.entries(SOUNDS)) {
  if (only.length && !only.includes(name)) continue;
  try {
    const stream = await client.textToSoundEffects.convert({
      text: s.text,
      durationSeconds: s.seconds,
      promptInfluence: 0.7,
      outputFormat: 'mp3_44100_128',
    });
    const chunks = [];
    for await (const c of stream) chunks.push(Buffer.from(c));
    const file = path.join(OUT, `sfx_${name}.mp3`);
    await writeFile(file, Buffer.concat(chunks));
    console.log(`✓ ${name} → ${path.relative(process.cwd(), file)} (${Buffer.concat(chunks).length} bytes)`);
  } catch (e) {
    console.error(`✗ ${name}: ${e.statusCode ?? ''} ${e.message ?? e}`);
    process.exitCode = 1;
  }
}
