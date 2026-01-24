"use client";

import { useEffect, useMemo, useState, type CSSProperties } from "react";

const dateFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric"
});

type ProgressItem = {
  id: string;
  title: string;
  start: Date;
  end: Date;
  accent: string;
};

const items: ProgressItem[] = [
  {
    id: "semester",
    title: "Semester progress",
    start: new Date(2025, 8, 2),
    end: new Date(2026, 1, 2),
    accent: "var(--accent-lilac)",
  },
  {
    id: "school-year",
    title: "School year progress",
    start: new Date(2025, 8, 2),
    end: new Date(2025, 5, 24),
    accent: "var(--accent-sky)",
  },
  {
    id: "high-school",
    title: "High school progress",
    start: new Date(2023, 8, 5),
    end: new Date(2027, 5, 25),
    accent: "var(--accent-mint)",
  }
];

const clamp = (value: number, min: number, max: number) =>
  Math.min(Math.max(value, min), max);

const normalizeRange = (start: number, end: number) => {
  if (end <= start) {
    return { start: end, end: start };
  }
  return { start, end };
};

const formatDate = (date: Date) => dateFormat.format(date);

const ProgressBar = ({ item, now }: { item: ProgressItem; now: number }) => {
  const startMs = item.start.getTime();
  const endMs = item.end.getTime();
  const normalized = normalizeRange(startMs, endMs);
  const total = normalized.end - normalized.start;
  const elapsed = clamp(now - normalized.start, 0, total);
  const ratio = total === 0 ? 0 : elapsed / total;
  const percent = Math.round(ratio * 1000) / 10;
  const daysLeft = Math.max(
    0,
    Math.ceil((normalized.end - now) / (1000 * 60 * 60 * 24))
  );

  return (
    <article className="card" style={{ "--accent": item.accent } as CSSProperties}>
      <div className="card-top">
        <h2>{item.title}</h2>
        <span className="percent" aria-label={`${percent}% complete`}>
          {percent}%
        </span>
      </div>
      <div className="range">
        <span>{formatDate(item.start)}</span>
        <span className="divider" aria-hidden="true">
          to
        </span>
        <span>{formatDate(item.end)}</span>
      </div>
      <div className="progress-track" role="progressbar" aria-valuenow={percent} aria-valuemin={0} aria-valuemax={100}>
        <div className="progress-fill" style={{ width: `${percent}%` }} />
        <div className="progress-glow" style={{ width: `${percent}%` }} />
      </div>
      <div className="meta">
        <span>{daysLeft} days left</span>
      </div>
    </article>
  );
};

export default function Home() {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const interval = setInterval(() => {
      setNow(Date.now());
    }, 60_000);

    return () => clearInterval(interval);
  }, []);

  const displayed = useMemo(() => items, []);

  return (
    <main className="page">
      <section className="cards">
        {displayed.map((item, index) => (
          <div key={item.id} style={{ animationDelay: `${0.1 + index * 0.12}s` }}>
            <ProgressBar item={item} now={now} />
          </div>
        ))}
      </section>
    </main>
  );
}
