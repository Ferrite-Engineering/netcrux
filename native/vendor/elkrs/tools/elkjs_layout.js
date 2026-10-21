// Lays out ELK JSON graphs with elkjs, the GWT build of the Java ELK, so the
// netlist corpus has an expectation that does not come from this crate.
//
//   npm install --prefix <dir> elkjs@0.9.3
//   NODE_PATH=<dir>/node_modules node tools/elkjs_layout.js <in.json> <out.json> [...]
//
// Arguments come in input/output pairs. Inputs ending in .gz are read
// gzipped.

const fs = require('fs');
const zlib = require('zlib');
const ELK = require('elkjs/lib/elk.bundled.js');

async function main(args) {
  if (args.length === 0 || args.length % 2 !== 0) {
    console.error('usage: elkjs_layout.js <in.json[.gz]> <out.json> [...]');
    process.exit(2);
  }
  const elk = new ELK();
  for (let i = 0; i < args.length; i += 2) {
    const raw = fs.readFileSync(args[i]);
    const text = args[i].endsWith('.gz') ? zlib.gunzipSync(raw) : raw;
    const result = await elk.layout(JSON.parse(text.toString('utf8')));
    fs.writeFileSync(args[i + 1], JSON.stringify(result));
    console.log(`${args[i]} -> ${args[i + 1]}`);
  }
}

main(process.argv.slice(2)).catch((e) => {
  console.error(e);
  process.exit(1);
});
