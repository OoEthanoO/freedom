"use client";

import { useEffect, useMemo, useState, type CSSProperties, useRef } from "react";

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
    title: "Semester",
    start: new Date(2025, 8, 2),
    end: new Date(2026, 1, 2),
    accent: "var(--accent-lilac)",
  },
  {
    id: "year",
    title: "School year",
    start: new Date(2025, 8, 2),
    end: new Date(2026, 5, 24),
    accent: "var(--accent-sky)",
  },
  {
    id: "school",
    title: "High school",
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
  const [unit, setUnit] = useState<"days" | "hours" | "seconds">("days");
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  
  const startMs = item.start.getTime();
  const endMs = item.end.getTime();
  const normalized = normalizeRange(startMs, endMs);
  const total = normalized.end - normalized.start;
  const elapsed = clamp(now - normalized.start, 0, total);
  const ratio = total === 0 ? 0 : elapsed / total;
  const percent = Math.round(ratio * 1000) / 10;
  
  const timeLeftMs = Math.max(0, normalized.end - now);
  const daysLeft = Math.ceil(timeLeftMs / (1000 * 60 * 60 * 24));
  const hoursLeft = Math.ceil(timeLeftMs / (1000 * 60 * 60));
  const secondsLeft = Math.ceil(timeLeftMs / 1000);

  const options: { value: "days" | "hours" | "seconds"; label: string }[] = [
    { value: "days", label: `${daysLeft} days left` },
    { value: "hours", label: `${hoursLeft} hours left` },
    { value: "seconds", label: `${secondsLeft} seconds left` },
  ];

  const currentLabel = options.find(opt => opt.value === unit)?.label;

  const shareUrl = typeof window !== "undefined" ? `${window.location.origin}/${item.id}/${unit}` : "";

  const copyShareLink = () => {
    if (shareUrl) {
      navigator.clipboard.writeText(shareUrl);
    }
  };

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener("mousedown", handleClickOutside);
      return () => document.removeEventListener("mousedown", handleClickOutside);
    }
  }, [isOpen]);

  return (
    <article className="row" style={{ "--accent": item.accent } as CSSProperties}>
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
      <div className="meta">
        <div className="dropdown" ref={dropdownRef}>
          <button
            className="dropdown-button"
            onClick={() => setIsOpen(!isOpen)}
            aria-label="Time left in different units"
            aria-expanded={isOpen}
          >
            {currentLabel}
          </button>
          {isOpen && (
            <div className="dropdown-menu">
              {options.map(option => (
                <button
                  key={option.value}
                  className={`dropdown-option ${option.value === unit ? "active" : ""}`}
                  onClick={() => {
                    setUnit(option.value);
                    setIsOpen(false);
                  }}
                >
                  {option.label}
                </button>
              ))}
            </div>
          )}
        </div>
        <button
          onClick={copyShareLink}
          style={{
            background: "linear-gradient(135deg, rgba(29, 29, 31, 0.04), rgba(29, 29, 31, 0.02))",
            border: "1px solid var(--stroke)",
            borderRadius: "6px",
            padding: "6px 10px",
            fontSize: "0.8rem",
            color: "var(--muted)",
            cursor: "pointer",
          }}
          aria-label="Copy share link"
        >
          Share
        </button>
      </div>
    </article>
  );
};

export default function Home() {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const interval = setInterval(() => {
      setNow(Date.now());
    }, 1_000);

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
      <footer className="footer">
        <div className="footer-inner">
          <a
            className="footer-made"
            href="https://ethanyanxu.com"
            target="_blank"
            rel="noopener noreferrer"
          >
            Made with ❤️ by Ethan Yan Xu
          </a>
          <a
            className="footer-contrib"
            href="https://www.rrashed.com/dean"
            target="_blank"
            rel="noopener noreferrer"
          >
            With contributions from Radean Rashed Mohassel
          </a>
        </div>
      </footer>
    </main>
  );
}
