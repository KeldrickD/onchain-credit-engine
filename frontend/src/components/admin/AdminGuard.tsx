"use client";

import { type ReactNode } from "react";

type AdminGuardProps = {
  isAdmin: boolean;
  isConnected: boolean;
  adminOnlyContent: ReactNode;
  readOnlyContent?: ReactNode;
  notConnectedContent: ReactNode;
};

export function AdminGuard({
  isAdmin,
  isConnected,
  adminOnlyContent,
  readOnlyContent,
  notConnectedContent,
}: AdminGuardProps) {
  if (!isConnected) {
    return <>{notConnectedContent}</>;
  }
  if (!isAdmin) {
    return (
      <>
        {readOnlyContent}
        <div className="mt-6 rounded-xl border border-amber-900/50 bg-amber-950/20 p-4">
          <p className="text-amber-600">Not authorized</p>
          <p className="mt-1 text-sm text-neutral-500">
            Connect with the admin address to enable write controls.
          </p>
        </div>
      </>
    );
  }
  return <>{adminOnlyContent}</>;
}
