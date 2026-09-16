import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "Progress tracker";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const getSemesterEnd = (now: number) => {
  const firstSemesterEnd = new Date(2027, 1, 3, 23, 59, 59);
  if (now > firstSemesterEnd.getTime()) {
    return new Date(2027, 4, 21, 23, 59, 59);
  }
  return firstSemesterEnd;
};

const items = {
  summer: { title: "Summer break", end: new Date(2026, 8, 7, 23, 59, 59) },
  winter: { title: "Winter break", end: new Date(2026, 11, 18, 23, 59, 59, 999) },
  semester: { title: "Semester", getEnd: getSemesterEnd },
  year: { title: "School year", end: new Date(2027, 4, 21, 23, 59, 59) },
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
  const end =
    "getEnd" in item && typeof (item as { getEnd?: (now: number) => Date }).getEnd === "function"
      ? (item as { getEnd: (now: number) => Date }).getEnd(now)
      : (item as { end: Date }).end;
  const timeLeftMs = Math.max(0, end.getTime() - now);
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
