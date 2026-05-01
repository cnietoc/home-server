import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Gatitos Aleatorios",
  description: "Gifs aleatorios de gatitos con animación 3D",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
