import { Metadata } from "next";
import { notFound } from "next/navigation";

type Target = "semester" | "year" | "school";
type Unit = "days" | "hours" | "seconds";

const dateFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric"
});

const items = {
  semester: {
    title: "Semester",
    start: new Date(2025, 8, 2),
    end: new Date(2026, 1, 2),
    accent: "var(--accent-lilac)",
  },
  year: {
    title: "School year",
    start: new Date(2025, 8, 2),
    end: new Date(2026, 5, 24),
    accent: "var(--accent-sky)",
  },
  school: {
    title: "High school",
    start: new Date(2023, 8, 5),
    end: new Date(2027, 5, 25),
    accent: "var(--accent-mint)",
  },
};

const calculateTimeLeft = (end: Date, unit: Unit): number => {
  const now = Date.now();
  const timeLeftMs = Math.max(0, end.getTime() - now);
  
  switch (unit) {
    case "days":
      return Math.ceil(timeLeftMs / (1000 * 60 * 60 * 24));
    case "hours":
      return Math.ceil(timeLeftMs / (1000 * 60 * 60));
    case "seconds":
      return Math.ceil(timeLeftMs / 1000);
  }
};

const formatTimeLeft = (timeLeft: number, unit: Unit): string => {
  const formatted = timeLeft.toLocaleString('en-US');
  return `${formatted} ${unit}`;
};

const calculateProgress = (start: Date, end: Date): number => {
  const now = Date.now();
  const startMs = start.getTime();
  const endMs = end.getTime();
  const total = endMs - startMs;
  const elapsed = Math.min(Math.max(now - startMs, 0), total);
  const ratio = total === 0 ? 0 : elapsed / total;
  return Math.round(ratio * 1000) / 10;
};

const formatDate = (date: Date) => dateFormat.format(date);

export async function generateMetadata({
  params,
}: {
  params: { target: string; unit: string };
}): Promise<Metadata> {
  const target = params.target as Target;
  const unit = params.unit as Unit;

  if (!items[target] || !["days", "hours", "seconds"].includes(unit)) {
    return {
      title: "Not Found",
    };
  }

  const item = items[target];
  const timeLeft = calculateTimeLeft(item.end, unit);
  const description = `${timeLeft} ${unit} left until ${item.title} ends`;

  return {
    title: `${item.title} - ${timeLeft} ${unit} left`,
    description,
    openGraph: {
      title: `${item.title}`,
      description,
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: `${item.title}`,
      description,
    },
  };
}

export default function SharePage({
  params,
}: {
  params: { target: string; unit: string };
}) {
  const target = params.target as Target;
  const unit = params.unit as Unit;

  if (!items[target] || !["days", "hours", "seconds"].includes(unit)) {
    notFound();
  }

  const item = items[target];
  const timeLeft = calculateTimeLeft(item.end, unit);
  const percent = calculateProgress(item.start, item.end);

  return (
    <main className="page">
      <section className="cards" style={{ maxWidth: "600px", margin: "0 auto" }}>
        <article className="row" style={{ "--accent": item.accent } as any}>
          <div className="row-top">
            <h2 className="row-title">{item.title}</h2>
            <span className="percent" aria-label={`${percent}% complete`}>
              {percent}%
            </span>
          </div>
          <div className="range">
            <span>{formatDate(item.start)}</span>
            <span>{formatDate(item.end)}</span>
          </div>
          <div className="progress-track" role="progressbar" aria-valuenow={percent} aria-valuemin={0} aria-valuemax={100}>
            <div className="progress-fill" style={{ width: `${percent}%` }} />
          </div>
          <div style={{ 
            marginTop: "16px", 
            textAlign: "center",
            fontSize: "2rem",
            fontWeight: "600",
            color: "var(--text)"
          }}>
            {formatTimeLeft(timeLeft, unit)} left
          </div>
        </article>
        <div style={{ textAlign: "center", marginTop: "32px" }}>
          <a
            href="/"
            style={{
              display: "inline-block",
              padding: "12px 24px",
              background: "linear-gradient(135deg, rgba(29, 29, 31, 0.06), rgba(29, 29, 31, 0.03))",
              border: "1px solid var(--stroke)",
              borderRadius: "8px",
              textDecoration: "none",
              color: "var(--text)",
              fontSize: "0.9rem",
              fontWeight: "500",
              transition: "all 0.2s ease",
            }}
          >
            ← View all progress
          </a>
        </div>
      </section>
    </main>
  );
}
