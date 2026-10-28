import { releaseResponse } from "./releases";
import type { ReleasesBucket } from "./releases";

interface Env {
  RELEASES: ReleasesBucket;
}

export default {
  fetch: async (request: Request, env: Env) =>
    (await releaseResponse(request, env.RELEASES)) ?? fetch(request),
} satisfies ExportedHandler<Env>;
