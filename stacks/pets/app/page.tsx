import PetGifViewer from "./PetGifViewer";

export default function Home() {
  return (
    <main
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: "2rem",
        padding: "2rem",
      }}
    >
      <h1
        style={{
          fontSize: "clamp(1.5rem, 5vw, 2.5rem)",
          fontWeight: 800,
          background: "linear-gradient(135deg, #ff00ff, #00ffff)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          backgroundClip: "text",
          letterSpacing: "-0.02em",
          textAlign: "center",
        }}
      >
        🐾 Gatitos y Perritos
      </h1>
      <PetGifViewer />
    </main>
  );
}
