import { Metadata } from "next";
import { notFound } from "next/navigation";

type Target = "semester" | "year" | "school";
type Unit = "days" | "hours" | "seconds";

const dateFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric"
});
const MS_PER_DAY = 24 * 60 * 60 * 1000;

const items: Record<Target, {
  title: string;
  accent: string;
  start?: Date;
  end?: Date;
  getRange?: (now: number) => { start: Date; end: Date };
}> = {
  semester: {
    title: "Semester",
    accent: "var(--accent-lilac)",
    getRange: (now: number) => {
      const cutoff = new Date(2026, 1, 2, 11, 45).getTime();
      if (now >= cutoff) {
        return {
          start: new Date(2026, 1, 2, 11, 45),
          end: new Date(2026, 5, 24, 0, 0),
        };
      }
      return {
        start: new Date(2025, 8, 2),
        end: new Date(2026, 1, 2, 11, 45),
      };
    },
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

const calculateDateDiffInDays = (end: Date, now: Date) => {
  const endUtc = Date.UTC(end.getFullYear(), end.getMonth(), end.getDate());
  const nowUtc = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.max(0, Math.round((endUtc - nowUtc) / MS_PER_DAY));
};

const calculateTimeLeft = (end: Date, unit: Unit): number => {
  const now = new Date();
  const timeLeftMs = Math.max(0, end.getTime() - now.getTime());
  
  switch (unit) {
    case "days":
      return calculateDateDiffInDays(end, now);
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

const resolveRange = (item: typeof items[Target]) => {
  if (item.getRange) {
    return item.getRange(Date.now());
  }
  return { start: item.start!, end: item.end! };
};

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
  const range = resolveRange(item);
  const timeLeft = calculateTimeLeft(range.end, unit);
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
  const range = resolveRange(item);
  const timeLeft = calculateTimeLeft(range.end, unit);
  const percent = calculateProgress(range.start, range.end);

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
            <span>{formatDate(range.start)}</span>
            <span>{formatDate(range.end)}</span>
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
