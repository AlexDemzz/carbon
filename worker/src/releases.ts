type ReleaseRange = { offset: number; length?: number } | { suffix: number };

interface ReleaseObject {
  body: ReadableStream;
  httpEtag: string;
  json: <Value>() => Promise<Value>;
  range?: ReleaseRange;
  size: number;
}

/** The slice of R2's `R2Bucket` that the release routes use. */
export interface ReleasesBucket {
  delete: (key: string) => Promise<void>;
  get: (
    key: string,
    options?: { range?: Headers }
  ) => Promise<ReleaseObject | null>;
  put: (
    key: string,
    value: string | ArrayBuffer | Uint8Array
  ) => Promise<unknown>;
}

interface LatestRelease {
  build: number;
  file: string;
  version: string;
}

const DMG_PATH = /^\/releases\/(?<name>[\w.-]+\.dmg)$/u;
const ONE_YEAR = 31_536_000;

const notFound = () => new Response("Not found", { status: 404 });

const download = async (bucket: ReleasesBucket) => {
  const latest = await bucket.get("latest.json");
  if (!latest) {
    return notFound();
  }
  const { file } = await latest.json<LatestRelease>();
  return new Response(null, {
    headers: { "Cache-Control": "no-store", Location: `/releases/${file}` },
    status: 302,
  });
};

const appcast = async (bucket: ReleasesBucket) => {
  const object = await bucket.get("appcast.xml");
  if (!object) {
    return notFound();
  }
  return new Response(object.body, {
    headers: {
      "Cache-Control": "max-age=300",
      "Content-Type": "application/rss+xml",
    },
  });
};

const servedBytes = ({ range, size }: ReleaseObject) => {
  if (!range) {
    return null;
  }
  if ("suffix" in range) {
    const length = Math.min(range.suffix, size);
    return { first: size - length, length };
  }
  const length = range.length ?? size - range.offset;
  return { first: range.offset, length };
};

const dmg = async (name: string, request: Request, bucket: ReleasesBucket) => {
  const object = await bucket.get(`releases/${name}`, {
    range: request.headers,
  });
  if (!object) {
    return notFound();
  }
  const headers = new Headers({
    "Accept-Ranges": "bytes",
    "Cache-Control": `public, max-age=${ONE_YEAR}, immutable`,
    "Content-Disposition": `attachment; filename="${name}"`,
    "Content-Type": "application/x-apple-diskimage",
    ETag: object.httpEtag,
  });
  const bytes = request.headers.has("Range") ? servedBytes(object) : null;
  if (!bytes) {
    headers.set("Content-Length", String(object.size));
    return new Response(object.body, { headers });
  }
  const last = bytes.first + bytes.length - 1;
  headers.set("Content-Length", String(bytes.length));
  headers.set("Content-Range", `bytes ${bytes.first}-${last}/${object.size}`);
  return new Response(object.body, { headers, status: 206 });
};

/** Answers the release routes from R2, or `undefined` to pass the request on to the landing Worker. */
export const releaseResponse = (
  request: Request,
  bucket: ReleasesBucket
): Promise<Response> | undefined => {
  if (request.method !== "GET") {
    return undefined;
  }
  const { pathname } = new URL(request.url);
  if (pathname === "/download") {
    return download(bucket);
  }
  if (pathname === "/appcast.xml") {
    return appcast(bucket);
  }
  const name = DMG_PATH.exec(pathname)?.groups?.name;
  if (name) {
    return dmg(name, request, bucket);
  }
  return undefined;
};
