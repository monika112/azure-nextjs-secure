export const dynamic = "force-dynamic";

export async function GET() {
  return Response.json({ status: "live" }, { status: 200 });
}