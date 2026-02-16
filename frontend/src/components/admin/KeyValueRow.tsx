"use client";

type KeyValueRowProps = {
  label: string;
  value: React.ReactNode;
};

export function KeyValueRow({ label, value }: KeyValueRowProps) {
  return (
    <div className="flex justify-between gap-4 py-1.5 text-sm">
      <span className="text-neutral-500">{label}</span>
      <span className="font-mono text-neutral-200">{value}</span>
    </div>
  );
}
