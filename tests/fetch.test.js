const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const F = require("../lib/fetch.js")
const C = require("../lib/collect.js")
const Model = require("../Model.js")
const { fileChanges } = require("../lib/web.js")

const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64")

test("every fetch is HTTPS only, with a time and a size limit", () => {
  const a = F.curlArgs("https://api.open-meteo.com/v1/forecast?x=1", F.JSON_MAX, 15)
  assert.equal(a[a.indexOf("--proto") + 1], "=https")
  assert.equal(a[a.indexOf("--proto-redir") + 1], "=https")
  assert.equal(a[a.indexOf("--max-filesize") + 1], String(F.JSON_MAX))
  assert.equal(a[a.indexOf("--max-time") + 1], "15")
  assert.deepEqual(a.slice(-2), ["--", "https://api.open-meteo.com/v1/forecast?x=1"], "the URL can't be read as a flag")
})

test("the fetcher refuses anything but HTTPS before curl runs", () => {
  for (const u of ["http://example.com/", "file:///etc/passwd", "-o/tmp/x", "", "https://user:pw@example.com/"]) assert.equal(C.fetchBytes(u, 100, 1, 1000), null, u)
})

test("photos come only from Wikimedia, over HTTPS", () => {
  assert.equal(F.httpsUrl("https://upload.wikimedia.org/a/b.jpg", F.IMAGE_HOSTS), "https://upload.wikimedia.org/a/b.jpg")
  assert.ok(F.httpsUrl("https://thumb.wikimedia.org/wikipedia/commons/thumb/d/de/a.jpg/3840px-a.jpg", F.IMAGE_HOSTS), "the summary API serves thumbnails from here")
  assert.equal(F.httpsUrl("http://upload.wikimedia.org/a/b.jpg", F.IMAGE_HOSTS), "")
  assert.equal(F.httpsUrl("https://upload.wikimedia.org.evil.example/b.jpg", F.IMAGE_HOSTS), "")
  assert.equal(F.httpsUrl("https://upload.wikimedia.org:8443/b.jpg", F.IMAGE_HOSTS), "")
  assert.equal(C.imageData("https://evil.example/a.jpg", 100), "")
})

test("a picture is what its bytes say, and only a raster photo passes", () => {
  assert.equal(F.sniffImage(PNG), "png")
  assert.equal(F.sniffImage(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0])), "jpeg")
  assert.equal(F.sniffImage(Buffer.from("RIFF\0\0\0\0WEBPVP8 ")), "webp")
  assert.equal(F.sniffImage(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>')), "")
  assert.equal(F.sniffImage(Buffer.from("push graphic-context\nimage over 0,0 0,0 'x'")), "")
  assert.equal(F.sniffImage(null), "")
})

test("ImageMagick is told the format and held to a budget", () => {
  const a = F.magickArgs("/tmp/q/in", "png", 900, 74, "/tmp/q/out.jpg")
  assert.ok(a.includes("png:/tmp/q/in[0]"))
  assert.equal(a[a.length - 1], "jpeg:/tmp/q/out.jpg")
  for (const k of ["memory", "area", "width", "height", "time"]) assert.ok(a.join(" ").includes("-limit " + k + " "), k)
})

test("a file that only claims to be a photo is never converted", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "daily-test-"))
  try {
    const fake = path.join(dir, "Lakeside.jpg")
    fs.writeFileSync(fake, '<svg xmlns="http://www.w3.org/2000/svg"><image href="file:///etc/passwd"/></svg>')
    assert.equal(C.imageData(fake, 100), "")
    const real = path.join(dir, "Ada.png")
    fs.writeFileSync(real, PNG)
    const out = C.imageData(real, 100)
    if (C.has("magick")) assert.match(out, /^data:image\/jpeg;base64,\/9j\//)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test("strings from someone else's API are strings, and not too long", () => {
  assert.equal(C.str({ toString: () => "<b>" }, 10), "")
  assert.equal(C.str(["a"], 10), "")
  assert.equal(C.str("abcdef", 3), "abc")
  assert.equal(C.str(1912, 10), "1912")
})

test("a cache too big to be real is ignored", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "daily-test-"))
  try {
    const f = path.join(dir, "forecast.json")
    fs.writeFileSync(f, '{"a":"' + "x".repeat(F.CACHE_JSON_MAX) + '"}')
    assert.equal(C.readJson(f), null)
    fs.writeFileSync(f, '{"a":1}')
    assert.deepEqual(C.readJson(f), { a: 1 })
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test("the index keeps only the edition's own path and bounded text", () => {
  const idx = Model.parseIndex(JSON.stringify({ editions: [
    { date: "2026-10-15", headline: "x".repeat(5000), path: "/home/ada/.local/share/quattro-daily/editions/2026-10-15.html" },
    { date: "2026-10-14", headline: { a: 1 }, path: "/home/ada/.ssh/id_ed25519" },
    { date: "2026-10-13", path: "/home/ada/x/../../ada/.local/share/quattro-daily/editions/2026-10-13.html" },
    { date: "2026-10-12", path: "https://evil.example/editions/2026-10-12.html" },
    { date: "2026-10-11/../../x" }
  ] }))
  assert.equal(idx.length, 4)
  assert.equal(idx[0].headline.length, 300)
  assert.equal(idx[0].path, "/home/ada/.local/share/quattro-daily/editions/2026-10-15.html")
  assert.equal(idx[1].headline, "")
  assert.equal(idx[1].path, "")
  assert.equal(idx[2].path, "")
  assert.equal(idx[3].path, "")
})

test("last time's state can't put a strange file name in the publishing prompt", () => {
  const c = fileChanges(["img/0123456789ab.jpg", "../../.ssh/id_ed25519", 'img/x", "y": "z', 7], ["img/aaaaaaaaaaaa.jpg"])
  assert.deepEqual(c.remove, ["img/0123456789ab.jpg"])
  assert.deepEqual(c.keep, ["img/aaaaaaaaaaaa.jpg"])
})
