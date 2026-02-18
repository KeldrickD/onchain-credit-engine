"use client";

const BASE_EXPLORER = "https://sepolia.basescan.org";

type TxLinkProps = {
  hash: `0x${string}`;
  children?: React.ReactNode;
  className?: string;
};

export function TxLink({ hash, children, className = "" }: TxLinkProps) {
  return (
    <a
      href={`${BASE_EXPLORER}/tx/${hash}`}
      target="_blank"
      rel="noreferrer"
      className={`text-emerald-500 hover:underline ${className}`}
    >
      {children ?? `${hash.slice(0, 10)}…`}
    </a>
  );
}
