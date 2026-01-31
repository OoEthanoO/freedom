import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "Progress tracker";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const items = {
  semester: { title: "Semester", end: new Date(2026, 1, 2) },
  year: { title: "School year", end: new Date(2026, 5, 24) },
  school: { title: "High school", end: new Date(2027, 5, 25) },
};

export default async function Image({
  params,
}: {
  params: { target: string; unit: string };
}) {
  const target = params.target as keyof typeof items;
  const unit = params.unit;
  const item = items[target];

  if (!item) return new ImageResponse(<div>Not Found</div>);

  const now = Date.now();
  const timeLeftMs = Math.max(0, item.end.getTime() - now);
  let timeLeft = 0;

  switch (unit) {
    case "days":
      timeLeft = Math.ceil(timeLeftMs / (1000 * 60 * 60 * 24));
      break;
    case "hours":
      timeLeft = Math.ceil(timeLeftMs / (1000 * 60 * 60));
      break;
    case "seconds":
      timeLeft = Math.ceil(timeLeftMs / 1000);
      break;
  }

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background: "#f5f5f7",
          fontFamily: "system-ui",
        }}
      >
        <h1 style={{ fontSize: 72, margin: 0 }}>{item.title}</h1>
        <p style={{ fontSize: 96, fontWeight: "bold", margin: 0, color: "#a8a4ff" }}>
          {timeLeft} {unit}
        </p>
        <p style={{ fontSize: 36, color: "#6e6e73" }}>left</p>
      </div>
    ),
    { ...size }
  );
}
