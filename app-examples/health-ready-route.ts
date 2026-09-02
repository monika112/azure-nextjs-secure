// Copy to app/api/health/ready/route.ts
export const dynamic = "force-dynamic";

export async function GET() {
  // Add only fast checks for dependencies required to serve requests.
  // Apply a short timeout; do not call optional downstream services here.
  return Response.json({ status: "ready" }, { status: 200 });
}
