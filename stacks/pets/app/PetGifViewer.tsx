"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import styles from "./PetGifViewer.module.css";

type PetType = "cat" | "dog";
type PetGif = { url: string; type: PetType };

const APIS: Record<PetType, string> = {
  cat: "https://api.thecatapi.com/v1/images/search?mime_types=gif&limit=5",
  dog: "https://api.thedogapi.com/v1/images/search?mime_types=gif&limit=5",
};

const LABELS: Record<PetType, string> = {
  cat: "🐱 Gatito",
  dog: "🐶 Perrito",
};

async function fetchBatch(): Promise<PetGif[]> {
  const [cats, dogs] = await Promise.allSettled([
    fetch(APIS.cat).then((r) => r.json() as Promise<{ url: string }[]>),
    fetch(APIS.dog).then((r) => r.json() as Promise<{ url: string }[]>),
  ]);

  const result: PetGif[] = [];
  if (cats.status === "fulfilled")
    cats.value.forEach((item) => result.push({ url: item.url, type: "cat" }));
  if (dogs.status === "fulfilled")
    dogs.value.forEach((item) => result.push({ url: item.url, type: "dog" }));

  // Shuffle so cats and dogs are interleaved randomly
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

function preload(url: string) {
  const img = new Image();
  img.src = url;
}

export default function PetGifViewer() {
  const [current, setCurrent] = useState<PetGif | null>(null);
  const [flipping, setFlipping] = useState(false);
  const queueRef = useRef<PetGif[]>([]);
  const isFetchingRef = useRef(false);

  const refillQueue = useCallback(async () => {
    if (isFetchingRef.current) return;
    isFetchingRef.current = true;
    try {
      const items = await fetchBatch();
      queueRef.current = [...queueRef.current, ...items];
    } catch {
      // retry silently on next cycle
    } finally {
      isFetchingRef.current = false;
    }
  }, []);

  const advance = useCallback(() => {
    const queue = queueRef.current;
    if (queue.length === 0) return;
    const next = queue.shift()!;
    setCurrent(next);
    if (queue[0]) preload(queue[0].url);
    if (queue.length < 3) refillQueue();
  }, [refillQueue]);

  useEffect(() => {
    (async () => {
      const items = await fetchBatch();
      queueRef.current = items;
      advance();
    })();
  }, [advance]);

  useEffect(() => {
    if (!current) return;

    const interval = setInterval(() => {
      setFlipping(true);

      const swapTimer = setTimeout(() => advance(), 400);
      const endTimer = setTimeout(() => setFlipping(false), 800);

      return () => {
        clearTimeout(swapTimer);
        clearTimeout(endTimer);
      };
    }, 5000);

    return () => clearInterval(interval);
  }, [current, advance]);

  return (
    <div className={styles.wrapper}>
      <div className={styles.scene}>
        <div className={`${styles.card} ${flipping ? styles.flipping : ""}`}>
          {current ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={current.url} alt={LABELS[current.type]} />
          ) : (
            <div className={styles.placeholder}>🐾</div>
          )}
        </div>
      </div>
      <div className={`${styles.label} ${current?.type === "dog" ? styles.dog : styles.cat}`}>
        {current ? LABELS[current.type] : "Cargando…"}
      </div>
    </div>
  );
}
