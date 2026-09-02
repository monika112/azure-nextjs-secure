// Copy to app/api/health/live/route.ts
export const dynamic = "force-dynamic";

export async function GET() {
  return Response.json({ status: "live" }, { status: 200 });
}
