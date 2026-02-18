"use client";

type SubjectKeyBadgeProps = {
  subjectKey: string;
  className?: string;
};

export function SubjectKeyBadge({ subjectKey, className = "" }: SubjectKeyBadgeProps) {
  const short = subjectKey.startsWith("0x") ? subjectKey.slice(0, 10) + "…" + subjectKey.slice(-8) : subjectKey;
  return (
    <code className={`rounded bg-neutral-800 px-2 py-0.5 text-xs font-mono text-neutral-300 ${className}`} title={subjectKey}>
      {short}
    </code>
  );
}
