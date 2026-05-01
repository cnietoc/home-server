"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import styles from "./CatGifViewer.module.css";

const CAT_API_URL =
  "https://api.thecatapi.com/v1/images/search?mime_types=gif&limit=10";

async function fetchBatch(): Promise<string[]> {
  const res = await fetch(CAT_API_URL);
  if (!res.ok) throw new Error("Cat API error");
  const data = (await res.json()) as { url: string }[];
  return data.map((item) => item.url);
}

function preload(url: string) {
  const img = new Image();
  img.src = url;
}

export default function CatGifViewer() {
  const [currentUrl, setCurrentUrl] = useState<string | null>(null);
  const [flipping, setFlipping] = useState(false);
  const queueRef = useRef<string[]>([]);
  const nextUrlRef = useRef<string | null>(null);
  const isFetchingRef = useRef(false);

  const refillQueue = useCallback(async () => {
    if (isFetchingRef.current) return;
    isFetchingRef.current = true;
    try {
      const urls = await fetchBatch();
      queueRef.current = [...queueRef.current, ...urls];
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
    setCurrentUrl(next);
    const upcoming = queue[0] ?? null;
    nextUrlRef.current = upcoming;
    if (upcoming) preload(upcoming);
    if (queue.length < 3) refillQueue();
  }, [refillQueue]);

  // Initial load
  useEffect(() => {
    (async () => {
      const urls = await fetchBatch();
      queueRef.current = urls;
      advance();
    })();
  }, [advance]);

  // Flip interval
  useEffect(() => {
    if (!currentUrl) return;

    const interval = setInterval(() => {
      // Start flip
      setFlipping(true);

      // At halfway point: swap the visible image
      const swapTimer = setTimeout(() => {
        advance();
      }, 400);

      // End flip
      const endTimer = setTimeout(() => {
        setFlipping(false);
      }, 800);

      return () => {
        clearTimeout(swapTimer);
        clearTimeout(endTimer);
      };
    }, 5000);

    return () => clearInterval(interval);
  }, [currentUrl, advance]);

  return (
    <div className={styles.scene}>
      <div className={`${styles.card} ${flipping ? styles.flipping : ""}`}>
        {currentUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={currentUrl} alt="Gatito aleatorio" />
        ) : (
          <div className={styles.placeholder}>🐱</div>
        )}
      </div>
    </div>
  );
}
