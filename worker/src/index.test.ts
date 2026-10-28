import { afterEach, expect, test, vi } from "vitest";

import worker from "./index";
import type { ReleasesBucket } from "./releases";

afterEach(() => {
  vi.unstubAllGlobals();
});

test("passes a path it doesn't serve on to the landing Worker", async () => {
  const landing = new Response("landing page");
  const origin = vi.fn(async () => landing);
  vi.stubGlobal("fetch", origin);
  const request = new Request("https://carbon.alexandrejoly.me/");

  const response = await worker.fetch(request, {
    RELEASES: {} as ReleasesBucket,
  });

  expect(origin).toHaveBeenCalledWith(request);
  expect(response).toBe(landing);
});
