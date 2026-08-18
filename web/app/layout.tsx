import './globals.css';

export const metadata = {
  title: 'NeoFL Control Room',
  description: 'NeoFL agentic trading intelligence control room',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
