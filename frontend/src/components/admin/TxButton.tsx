"use client";

import { type ReactNode } from "react";

type TxButtonProps = {
  onClick: () => void;
  disabled?: boolean;
  pending?: boolean;
  pendingLabel?: string;
  children: ReactNode;
  className?: string;
};

export function TxButton({
  onClick,
  disabled,
  pending,
  pendingLabel = "Confirming…",
  children,
  className = "rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50",
}: TxButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled || pending}
      className={className}
    >
      {pending ? pendingLabel : children}
    </button>
  );
}
