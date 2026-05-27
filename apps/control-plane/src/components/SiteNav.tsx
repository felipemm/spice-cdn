import Link from "next/link";

export function SiteNav() {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3">
        <Link href="/" className="font-semibold tracking-tight text-neutral-100">
          Spice control plane
        </Link>
        <nav className="flex gap-4 text-sm text-neutral-300">
          <Link href="/" className="hover:text-white">
            Instances
          </Link>
          <Link href="/instances/new" className="hover:text-white">
            New
          </Link>
          <Link href="/cluster-urls" className="hover:text-white">
            Cluster URLs
          </Link>
          <Link href="/admin" className="hover:text-amber-200">
            Admin
          </Link>
        </nav>
      </div>
    </header>
  );
}
