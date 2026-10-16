const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const qml = fs.readdirSync(root).filter(f => f.endsWith(".qml"))

test("the manifest's entry points exist and every default has a schema row", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.id, "atsokolas.daily")
  for (const file of Object.values(manifest.entryPoints)) assert.ok(fs.existsSync(path.join(root, file)), file)
  const keys = manifest.barWidget.schema.map(s => s.key)
  for (const key of Object.keys(manifest.barWidget.defaults)) assert.ok(keys.includes(key), key)
})

test("colours come from the theme file, never the shell's Color singleton", () => {
  for (const file of qml) assert.doesNotMatch(read(file), /\bColor\./, file)
})

test("the panel uses the scoped bar API for hover reveal", () => {
  const panel = read("Panel.qml")
  assert.match(panel, /typeof root\.bar\.setCenterHoverRevealSuppressed === "function"/)
  assert.doesNotMatch(panel, /root\.bar\.centerHoverRevealSuppressed\s*=/)
})

test("the builder is executable and runs on node", () => {
  const file = path.join(root, "bin/quattro-daily-build")
  assert.ok(fs.statSync(file).mode & 0o111)
  assert.match(fs.readFileSync(file, "utf8"), /^#!\/usr\/bin\/env node/)
})

test("headlines from the editions print as plain text, never rich text", () => {
  const panel = read("Panel.qml")
  for (const field of ["current.title", "current.kicker", "current.headline", "modelData.headline"]) {
    const at = panel.indexOf(field)
    assert.ok(at > 0, field)
    assert.match(panel.slice(at, at + 160), /textFormat: Text\.PlainText/, field)
  }
})
