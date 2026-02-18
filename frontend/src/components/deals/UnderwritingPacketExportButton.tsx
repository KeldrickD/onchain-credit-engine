"use client";

import {
  buildUnderwritingPacket,
  downloadUnderwritingPacket,
  type UnderwritingPacketV0,
} from "@/lib/underwriting-packet";

type UnderwritingPacketExportButtonProps = {
  buildPacket: () => UnderwritingPacketV0;
  dealIdShort?: string;
  className?: string;
};

export function UnderwritingPacketExportButton({
  buildPacket,
  dealIdShort,
  className = "",
}: UnderwritingPacketExportButtonProps) {
  const handleExport = () => {
    const packet = buildPacket();
    downloadUnderwritingPacket(packet, dealIdShort);
  };

  return (
    <button
      type="button"
      onClick={handleExport}
      className={`rounded-lg border border-neutral-600 bg-neutral-800 px-4 py-2 text-sm font-medium text-neutral-200 hover:bg-neutral-700 ${className}`}
    >
      Export Underwriting Packet
    </button>
  );
}
