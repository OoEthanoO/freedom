export const dynamic = "force-dynamic";

export function GET() {
  return Response.json(
    {
      status: "ok",
      service: "freedom",
      commit: process.env.FREEDOM_COMMIT_SHA ?? "development"
    },
    { headers: { "Cache-Control": "no-store" } }
  );
}
