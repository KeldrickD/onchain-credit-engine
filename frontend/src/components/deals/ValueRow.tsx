"use client";

type ValueRowProps = {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
};

export function ValueRow({ label, value, mono }: ValueRowProps) {
  return (
    <div className="flex justify-between gap-4 py-1">
      <span className="text-sm text-neutral-500 shrink-0">{label}</span>
      <span className={`text-right text-sm ${mono ? "font-mono" : ""}`}>{value}</span>
    </div>
  );
}
