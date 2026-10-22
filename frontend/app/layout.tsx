import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Smart Manufacturing Industrial AI | Polyglot Microservices Cockpit',
  description: 'Enterprise Polyglot Industrial MLOps Cockpit (Rust + Go + Python + Next.js) with Active-Passive Multi-Cloud Disaster Recovery',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="min-h-screen bg-industrial-950 text-slate-100 antialiased selection:bg-cyan-500 selection:text-black">
        {children}
      </body>
    </html>
  );
}
