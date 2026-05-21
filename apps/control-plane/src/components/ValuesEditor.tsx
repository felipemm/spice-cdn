"use client";

import dynamic from "next/dynamic";
import { useMemo } from "react";

const Editor = dynamic(() => import("@monaco-editor/react"), { ssr: false });

type Props = {
  value: string;
  onChange: (v: string) => void;
};

export function ValuesEditor({ value, onChange }: Props) {
  const options = useMemo(
    () => ({
      minimap: { enabled: false },
      fontSize: 13,
      wordWrap: "on" as const,
      scrollBeyondLastLine: false,
    }),
    [],
  );

  return (
    <div className="h-[480px] w-full overflow-hidden rounded border border-neutral-700">
      <Editor
        height="100%"
        defaultLanguage="yaml"
        theme="vs-dark"
        value={value}
        onChange={(v) => onChange(v ?? "")}
        options={options}
      />
    </div>
  );
}
