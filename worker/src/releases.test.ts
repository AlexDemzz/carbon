import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { getPlatformProxy } from "wrangler";
import type { PlatformProxy } from "wrangler";

import { releaseResponse } from "./releases";
import type { ReleasesBucket } from "./releases";

const site = "https://carbon.alexandrejoly.me";

let platform: PlatformProxy<{ RELEASES: ReleasesBucket }>;
let bucket: ReleasesBucket;

beforeAll(async () => {
  // Miniflare with the local R2 bucket bound in wrangler.jsonc, kept in memory.
  platform = await getPlatformProxy({ persist: false });
  bucket = platform.env.RELEASES;
});

afterAll(async () => {
  await platform.dispose();
});

const get = (path: string, headers?: HeadersInit) =>
  releaseResponse(new Request(`${site}${path}`, { headers }), bucket);

describe("/download", () => {
  test("redirects to the DMG named in latest.json, uncached", async () => {
    await bucket.put(
      "latest.json",
      JSON.stringify({ build: 42, file: "Carbon-1.2.0.dmg", version: "1.2.0" })
    );

    const response = await get("/download");

    expect(response?.status).toBe(302);
    expect(response?.headers.get("Location")).toBe(
      "/releases/Carbon-1.2.0.dmg"
    );
    expect(response?.headers.get("Cache-Control")).toBe("no-store");
  });

  test("is not found before the first release", async () => {
    await bucket.delete("latest.json");

    const response = await get("/download");

    expect(response?.status).toBe(404);
  });
});

describe("/appcast.xml", () => {
  test("serves the appcast as RSS, cached for five minutes", async () => {
    const appcast = '<?xml version="1.0"?><rss version="2.0"><channel/></rss>';
    await bucket.put("appcast.xml", appcast);

    const response = await get("/appcast.xml");

    expect(response?.status).toBe(200);
    expect(response?.headers.get("Content-Type")).toBe("application/rss+xml");
    expect(response?.headers.get("Cache-Control")).toBe("max-age=300");
    expect(await response?.text()).toBe(appcast);
  });
});

describe("/releases/<name>.dmg", () => {
  const dmg = "0123456789abcdef";

  beforeAll(async () => {
    await bucket.put("releases/Carbon-1.2.0.dmg", dmg);
  });

  test("streams the DMG as an immutable attachment", async () => {
    const response = await get("/releases/Carbon-1.2.0.dmg");

    expect(response?.status).toBe(200);
    expect(response?.headers.get("Content-Type")).toBe(
      "application/x-apple-diskimage"
    );
    expect(response?.headers.get("Content-Disposition")).toBe(
      'attachment; filename="Carbon-1.2.0.dmg"'
    );
    expect(response?.headers.get("Cache-Control")).toBe(
      "public, max-age=31536000, immutable"
    );
    expect(response?.headers.get("Accept-Ranges")).toBe("bytes");
    expect(response?.headers.get("Content-Length")).toBe("16");
    expect(await response?.text()).toBe(dmg);
  });

  test("answers a range request with the requested bytes", async () => {
    const response = await get("/releases/Carbon-1.2.0.dmg", {
      Range: "bytes=4-7",
    });

    expect(response?.status).toBe(206);
    expect(response?.headers.get("Content-Range")).toBe("bytes 4-7/16");
    expect(response?.headers.get("Content-Length")).toBe("4");
    expect(await response?.text()).toBe("4567");
  });

  test("is not found for a name that was never released", async () => {
    const response = await get("/releases/Carbon-9.9.9.dmg");

    expect(response?.status).toBe(404);
  });
});

describe("other requests", () => {
  test("are left to the landing Worker", async () => {
    await bucket.put(
      "latest.json",
      JSON.stringify({ build: 42, file: "Carbon-1.2.0.dmg", version: "1.2.0" })
    );

    expect(await get("/")).toBeUndefined();
    expect(await get("/releases/notes.txt")).toBeUndefined();
    expect(
      await releaseResponse(
        new Request(`${site}/download`, { method: "POST" }),
        bucket
      )
    ).toBeUndefined();
  });
});
