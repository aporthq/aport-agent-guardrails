// Copy the one protocol owner into independently published npm artifacts.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
for (const relative of ['packages/core/dist/installation-reporting', 'extensions/openclaw-aport/installation-reporting']) {
  const dest = path.join(root, relative);
  fs.mkdirSync(dest, { recursive: true });
  for (const name of fs.readdirSync(path.join(root, 'src/installation-reporting'))) {
    if (name.endsWith('.js')) fs.copyFileSync(path.join(root, 'src/installation-reporting', name), path.join(dest, name));
  }
  fs.writeFileSync(path.join(dest, 'package.json'), '{"type":"commonjs"}\n');
}
